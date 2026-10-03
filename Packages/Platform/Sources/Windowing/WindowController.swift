import AppKit
import Observation
import SwiftUI
import VortexCore

/// Why the window opens. It decides where the window appears.
public enum OpenReason: Equatable, Sendable {
  case hover
  case click
  case hotkey
  case menuBarIcon
  case fileDrag
}

/// What happens around the notch, the window and the menu bar icon.
public enum WindowEvent: Equatable, Sendable {
  case notchHoverChanged(isInside: Bool)
  case notchClicked
  case fileDragEnteredNotch
  case menuBarIconClicked
  case filesDroppedOnMenuBarIcon([URL])
  case pointerInsideWindowChanged(isInside: Bool)
  case clickedOutside
  case escapePressed
  case screensChanged(hasNotch: Bool)
}

/// Owns everything Vortex puts on screen: the closed notch with its ears, the window that grows out of the
/// notch (or drops under the menu bar icon on screens without one) and the menu bar icon.
///
/// It only draws and reports events; what to do with them is decided by the shell.
@MainActor
public final class WindowController: NSObject {
  public static let shared = WindowController()

  private struct Ears {
    let panel: VortexPanel
    let model: EarsModel
    let notch: CGRect
  }

  private struct Placement {
    let frame: CGRect
    let mode: WindowPresentationModel.Mode
  }

  private let presentation = WindowPresentationModel()
  private var content = AnyView(EmptyView())
  private var indicators: NotchIndicatorCenter?
  private var mainPanel: VortexPanel?
  private var ears: [CGDirectDisplayID: Ears] = [:]
  private var menuBarItem: NSStatusItem?
  private var menuBarMenu: NSMenu?
  /// Off until the shell applies the user's setting, so a hidden icon never flashes at launch.
  private var isMenuBarIconWanted = false
  private var outsideClickMonitor: Any?
  private var screenObserver: NSObjectProtocol?
  /// Incremented on every present and dismiss, so a finished animation never acts on a newer one.
  private var generation = 0
  private var emit: (WindowEvent) -> Void = { _ in }
  private var finishEvents: () -> Void = {}

  override private init() {
    super.init()
  }

  // MARK: - Setup

  /// Puts the notch, the window content and the menu bar icon on screen. Call once at launch.
  public func install(content: some View, menu: NSMenu, indicators: NotchIndicatorCenter) {
    self.content = AnyView(content)
    self.menuBarMenu = menu
    self.indicators = indicators
    presentation.onNotchTapped = { [weak self] in self?.emit(.notchClicked) }
    rebuildEars()
    observeIndicators()
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.screensChanged() }
    }
  }

  /// Events for the shell. A new stream ends the previous one.
  public func events() -> AsyncStream<WindowEvent> {
    let (stream, continuation) = AsyncStream.makeStream(of: WindowEvent.self)
    finishEvents()
    emit = { continuation.yield($0) }
    finishEvents = { continuation.finish() }
    return stream
  }

  public var hasNotchedScreen: Bool {
    NSScreen.screens.contains { $0.notchRect != nil }
  }

  // MARK: - Window

  public func present(_ reason: OpenReason) {
    guard let placement = placement(for: reason) else { return }
    let panel = mainPanel ?? makeMainPanel()
    generation += 1
    let current = generation

    if !panel.isVisible { presentation.isExpanded = false }
    presentation.mode = placement.mode
    panel.hasShadow = false
    panel.setFrame(placement.frame, display: true)
    panel.orderFrontRegardless()
    panel.makeKey()
    panel.contentView?.updateTrackingAreas()
    emit(.pointerInsideWindowChanged(isInside: placement.frame.contains(NSEvent.mouseLocation)))
    installOutsideClickMonitor()

    // Expand on the next run loop turn, after the collapsed state has been drawn once.
    Task { @MainActor [weak self] in
      guard let self, self.generation == current else { return }
      withAnimation(self.openAnimation) {
        self.presentation.isExpanded = true
      } completion: { [weak self] in
        guard let self, self.generation == current else { return }
        panel.hasShadow = true
        panel.invalidateShadow()
      }
    }
  }

  public func dismiss() {
    removeOutsideClickMonitor()
    guard let panel = mainPanel, panel.isVisible else { return }
    generation += 1
    let current = generation
    panel.hasShadow = false
    withAnimation(closeAnimation) {
      presentation.isExpanded = false
    } completion: { [weak self] in
      guard let self, self.generation == current else { return }
      panel.orderOut(nil)
    }
  }

  private func makeMainPanel() -> VortexPanel {
    let panel = VortexPanel(acceptsKey: true)
    let root = PointerTrackingView()
    root.onPointerInsideChanged = { [weak self] isInside in
      self?.emit(.pointerInsideWindowChanged(isInside: isInside))
    }
    let hosting = NSHostingView(rootView: WindowChromeView(model: presentation, content: content))
    hosting.sizingOptions = []
    hosting.autoresizingMask = [.width, .height]
    root.addSubview(hosting)
    panel.contentView = root
    hosting.frame = root.bounds
    panel.onEscape = { [weak self] in self?.emit(.escapePressed) }
    mainPanel = panel
    return panel
  }

  private func placement(for reason: OpenReason) -> Placement? {
    let pointer = NSEvent.mouseLocation
    let pointerScreen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
    let screen: NSScreen?
    switch reason {
    case .hover, .click, .fileDrag:
      screen = NSScreen.screens.first { $0.notchRect != nil && NSMouseInRect(pointer, $0.frame, false) }
        ?? NSScreen.screens.first { $0.notchRect != nil }
        ?? pointerScreen
    case .hotkey:
      screen = pointerScreen
    case .menuBarIcon:
      screen = menuBarItem?.button?.window?.screen ?? pointerScreen
    }
    guard let screen else { return nil }

    let size = VortexMetrics.windowSize
    if let notch = screen.notchRect {
      return Placement(
        frame: ScreenGeometry.notchWindowFrame(notch: notch, screenFrame: screen.frame, size: size, shoulder: VortexMetrics.shoulder),
        mode: .notch(notch.size)
      )
    }
    let iconFrame = menuBarItem?.button?.window.flatMap { $0.screen == screen ? $0.frame : nil }
    let anchor = iconFrame ?? CGRect(x: screen.visibleFrame.maxX - 60, y: screen.visibleFrame.maxY, width: 1, height: 1)
    return Placement(
      frame: ScreenGeometry.menuBarWindowFrame(anchor: anchor, visibleFrame: screen.visibleFrame, size: size),
      mode: .menuBar
    )
  }

  private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  private var openAnimation: Animation {
    reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)
  }

  private var closeAnimation: Animation {
    reduceMotion ? .easeIn(duration: 0.12) : .spring(response: 0.26, dampingFraction: 1)
  }

  // MARK: - Outside clicks

  private func installOutsideClickMonitor() {
    guard outsideClickMonitor == nil else { return }
    // Global monitors only see clicks in other apps; clicks in our own panels never arrive here.
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
      MainActor.assumeIsolated { self?.emit(.clickedOutside) }
    }
  }

  private func removeOutsideClickMonitor() {
    guard let monitor = outsideClickMonitor else { return }
    NSEvent.removeMonitor(monitor)
    outsideClickMonitor = nil
  }

  // MARK: - Closed notch

  private func rebuildEars() {
    ears.values.forEach { $0.panel.orderOut(nil) }
    ears.removeAll()
    for screen in NSScreen.screens {
      guard let notch = screen.notchRect else { continue }
      let model = EarsModel()
      model.notchSize = notch.size
      let panel = VortexPanel(acceptsKey: false)
      let hit = NotchHitView()
      hit.onHoverChanged = { [weak self] isInside in self?.emit(.notchHoverChanged(isInside: isInside)) }
      hit.onClick = { [weak self] in self?.emit(.notchClicked) }
      hit.onFileDragEntered = { [weak self] in self?.emit(.fileDragEnteredNotch) }
      let hosting = NSHostingView(rootView: NotchEarsView(model: model))
      hosting.sizingOptions = []
      hosting.autoresizingMask = [.width, .height]
      hit.addSubview(hosting)
      panel.contentView = hit
      hosting.frame = hit.bounds
      let entry = Ears(panel: panel, model: model, notch: notch)
      ears[screen.displayID] = entry
      layOut(entry)
      panel.orderFrontRegardless()
    }
    updateMenuBarIcon()
  }

  private func layOut(_ entry: Ears) {
    let current = indicators?.ears ?? NotchEars()
    let earWidth = EarsMetrics.earWidth(for: current)
    entry.model.ears = current
    entry.model.earWidth = earWidth
    let shoulder = earWidth > 0 ? VortexMetrics.shoulder : 0
    entry.panel.setFrame(ScreenGeometry.earsFrame(notch: entry.notch, earWidth: earWidth, shoulder: shoulder), display: true)
  }

  private func observeIndicators() {
    guard let indicators else { return }
    withObservationTracking {
      _ = indicators.ears
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.ears.values.forEach(self.layOut)
        self.updateMenuBarTitle()
        self.observeIndicators()
      }
    }
  }

  private func screensChanged() {
    rebuildEars()
    emit(.screensChanged(hasNotch: hasNotchedScreen))
  }

  // MARK: - Menu bar icon

  public func setMenuBarIconVisible(_ isVisible: Bool) {
    isMenuBarIconWanted = isVisible
    updateMenuBarIcon()
  }

  private func updateMenuBarIcon() {
    if isMenuBarIconWanted {
      if menuBarItem == nil { menuBarItem = makeMenuBarItem() }
      updateMenuBarTitle()
    } else if let item = menuBarItem {
      NSStatusBar.system.removeStatusItem(item)
      menuBarItem = nil
    }
  }

  private func makeMenuBarItem() -> NSStatusItem {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
      button.image = VortexGlyph.menuBarImage()
      button.imagePosition = .imageLeading
      button.target = self
      button.action = #selector(menuBarIconPressed(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
      let drop = FileDropView(frame: button.bounds)
      drop.autoresizingMask = [.width, .height]
      drop.onDrop = { [weak self] urls in self?.emit(.filesDroppedOnMenuBarIcon(urls)) }
      button.addSubview(drop)
    }
    return item
  }

  @objc private func menuBarIconPressed(_ sender: NSStatusBarButton) {
    let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
      || NSApp.currentEvent?.modifierFlags.contains(.control) == true
    if isRightClick, let item = menuBarItem, let menu = menuBarMenu {
      item.menu = menu
      item.button?.performClick(nil)
      item.menu = nil
    } else {
      emit(.menuBarIconClicked)
    }
  }

  /// Without a notch the indicators live next to the menu bar icon.
  private func updateMenuBarTitle() {
    guard let button = menuBarItem?.button else { return }
    let text = hasNotchedScreen ? "" : (indicators?.ears.menuBarText ?? "")
    button.title = text.isEmpty ? "" : " \(text)"
  }
}
