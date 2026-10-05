import AppKit
import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// Why the window opens. It decides where the window appears and how it behaves.
enum OpenReason: Equatable, Sendable {
  case hover
  case click
  case hotkey
  case menuBarIcon
  case fileDrag

  /// Opened on the way past the notch rather than on purpose: such a window closes when the pointer
  /// leaves it and does not take keyboard focus away from the app the user is typing in.
  var isPassing: Bool {
    self == .hover || self == .fileDrag
  }
}

/// What happens around the notch, the window and the menu bar icon.
enum WindowEvent: Equatable, Sendable {
  case notchHoverChanged(isInside: Bool)
  case notchClicked
  case fileDragEnteredNotch
  case menuBarIconClicked
  case filesDroppedOnMenuBarIcon([URL])
  case pointerInsideWindowChanged(isInside: Bool)
  /// Something of Vortex's is in use outside the window (a drag out of it, Quick Look, the folder picker), or no more.
  case outsideActivityChanged(isActive: Bool)
  case clickedOutside
  case escapePressed
  /// Sent when the events start and whenever displays change.
  case screensChanged(everyScreenHasNotch: Bool)
}

/// Owns everything Vortex puts on screen: the closed notch with its ears, the window that grows out of the
/// notch (or drops under the menu bar icon on screens without one) and the menu bar icon.
///
/// It only draws and reports events; what to do with them is decided by ShellFeature.
@MainActor
final class WindowController: NSObject {
  static let shared = WindowController()

  private struct Ears {
    let panel: VortexPanel
    let hit: NotchHitView
    let model: EarsModel
    let notch: CGRect
    /// Shown only while the notch flashes; it never takes clicks.
    let glowPanel: VortexPanel
    let glow: GlowModel
  }

  private struct Placement {
    let frame: CGRect
    let notch: CGSize?
  }

  @SharedReader(.notchIndicators) private var indicators
  private let presentation = WindowPresentationModel()
  private var mainPanel: VortexPanel?
  private var ears: [CGDirectDisplayID: Ears] = [:]
  private var currentEars = NotchEars()
  /// The last flash number seen per feature, see `NotchEars.flash`.
  private var seenFlashes: [FeatureID: Int] = [:]
  /// Incremented on every flash, so an older flash never hides the glow of a newer one.
  private var flashGeneration = 0
  private var indicatorsObservation: ObserveToken?
  private var outsideActivityObservation: ObserveToken?
  private var menuBarItem: NSStatusItem?
  private var menuBarMenu: NSMenu?
  /// Off until the shell applies the user's setting, so a hidden icon never flashes at launch.
  private var isMenuBarIconWanted = false
  /// Whether some feature takes files, so files may be dropped on the menu bar icon.
  private var acceptsFiles = false
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

  /// Puts the notch on screen and builds the window, so the first open does not wait for it. Call once at launch.
  func install(content: some View, menu: NSMenu) {
    menuBarMenu = menu
    presentation.notch = NSScreen.screens.lazy.compactMap(\.notchRect).first?.size
    presentation.onNotchTapped = { [weak self] in self?.emit(.notchClicked) }
    mainPanel = makeMainPanel(content: AnyView(content))
    rebuildEars()
    indicatorsObservation = observe { [weak self] in self?.indicatorsChanged() }
    outsideActivityObservation = observe { [weak self] in
      self?.outsideActivityChanged(OutsideActivity.shared.isActive)
    }
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.screensChanged() }
    }
  }

  /// Events for the shell, starting with the current screen layout. A new stream ends the previous one.
  func events() -> AsyncStream<WindowEvent> {
    let (stream, continuation) = AsyncStream.makeStream(of: WindowEvent.self)
    finishEvents()
    emit = { continuation.yield($0) }
    finishEvents = { continuation.finish() }
    continuation.yield(.screensChanged(everyScreenHasNotch: everyScreenHasNotch))
    return stream
  }

  private var everyScreenHasNotch: Bool {
    NSScreen.screens.allSatisfy { $0.notchRect != nil }
  }

  // MARK: - Window

  func present(_ reason: OpenReason) {
    guard let panel = mainPanel, let placement = placement(for: reason) else { return }
    generation += 1
    let current = generation

    if !panel.isVisible { presentation.isExpanded = false }
    presentation.notch = placement.notch
    panel.hasShadow = false
    panel.setFrame(placement.frame, display: true)
    panel.orderFrontRegardless()
    if !reason.isPassing { panel.makeKey() }
    panel.contentView?.updateTrackingAreas()
    // NSMouseInRect counts the top edge in, where a pointer pushed against the notch sits.
    emit(.pointerInsideWindowChanged(isInside: NSMouseInRect(NSEvent.mouseLocation, placement.frame, false)))
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

  func dismiss() {
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
      self.resetNotchHover()
    }
  }

  private func makeMainPanel(content: AnyView) -> VortexPanel {
    let root = HoverTrackingView()
    root.onHoverChanged = { [weak self] isInside in
      self?.emit(.pointerInsideWindowChanged(isInside: isInside))
    }
    let panel = VortexPanel(acceptsKey: true, root: root, content: WindowChromeView(model: presentation, content: content))
    panel.onEscape = { [weak self] in self?.emit(.escapePressed) }
    // Lay the content out once while hidden, so opening only has to animate it.
    let shoulder = presentation.notch == nil ? 0 : VortexMetrics.shoulder
    let size = VortexMetrics.windowSize
    panel.setFrame(CGRect(x: 0, y: 0, width: size.width + shoulder * 2, height: size.height), display: false)
    root.layoutSubtreeIfNeeded()
    return panel
  }

  private func placement(for reason: OpenReason) -> Placement? {
    let pointer = NSEvent.mouseLocation
    let pointerScreen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
    let screen: NSScreen? = switch reason {
    case .hover, .click, .fileDrag:
      NSScreen.screens.first { $0.notchRect != nil && NSMouseInRect(pointer, $0.frame, false) }
        ?? NSScreen.screens.first { $0.notchRect != nil }
        ?? pointerScreen
    case .hotkey:
      pointerScreen
    case .menuBarIcon:
      menuBarItem?.button?.window?.screen ?? pointerScreen
    }
    guard let screen else { return nil }

    let size = VortexMetrics.windowSize
    if let notch = screen.notchRect {
      return Placement(
        frame: ScreenGeometry.notchWindowFrame(notch: notch, screenFrame: screen.frame, size: size, shoulder: VortexMetrics.shoulder),
        notch: notch.size
      )
    }
    let iconFrame = menuBarItem?.button?.window.flatMap { $0.screen == screen ? $0.frame : nil }
    let anchor = iconFrame ?? CGRect(x: screen.visibleFrame.maxX - 60, y: screen.visibleFrame.maxY, width: 1, height: 1)
    return Placement(
      frame: ScreenGeometry.menuBarWindowFrame(anchor: anchor, visibleFrame: screen.visibleFrame, size: size),
      notch: nil
    )
  }

  private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  private var openAnimation: Animation {
    reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82)
  }

  private var closeAnimation: Animation {
    reduceMotion ? .easeIn(duration: 0.12) : .spring(response: 0.26, dampingFraction: 1)
  }

  /// Tracking areas say nothing while a drag runs; once the activity ends, the pointer may be anywhere.
  private func outsideActivityChanged(_ isActive: Bool) {
    emit(.outsideActivityChanged(isActive: isActive))
    if !isActive, let panel = mainPanel, panel.isVisible {
      emit(.pointerInsideWindowChanged(isInside: NSMouseInRect(NSEvent.mouseLocation, panel.frame, false)))
    }
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
    ears.values.forEach {
      $0.panel.orderOut(nil)
      $0.glowPanel.orderOut(nil)
    }
    ears.removeAll()
    for screen in NSScreen.screens {
      guard let notch = screen.notchRect else { continue }
      let model = EarsModel()
      model.notchSize = notch.size
      let hit = NotchHitView()
      hit.onHoverChanged = { [weak self] isInside in self?.emit(.notchHoverChanged(isInside: isInside)) }
      hit.onClick = { [weak self] in self?.emit(.notchClicked) }
      hit.onFileDragEntered = { [weak self] in self?.emit(.fileDragEnteredNotch) }
      let glow = GlowModel()
      let glowPanel = VortexPanel(acceptsKey: false, root: NSView(), content: NotchGlowView(model: glow))
      glowPanel.ignoresMouseEvents = true
      let entry = Ears(
        panel: VortexPanel(acceptsKey: false, root: hit, content: NotchEarsView(model: model)),
        hit: hit,
        model: model,
        notch: notch,
        glowPanel: glowPanel,
        glow: glow
      )
      ears[screen.displayID] = entry
      layOut(entry)
      entry.panel.orderFrontRegardless()
    }
    updateMenuBarIcon()
  }

  private func layOut(_ entry: Ears) {
    let earWidth = EarsMetrics.earWidth(for: currentEars)
    entry.model.ears = currentEars
    entry.model.earWidth = earWidth
    let shoulder = earWidth > 0 ? VortexMetrics.shoulder : 0
    entry.panel.setFrame(ScreenGeometry.earsFrame(notch: entry.notch, earWidth: earWidth, shoulder: shoulder), display: true)

    let silhouette = CGSize(width: entry.notch.width + earWidth * 2, height: entry.notch.height)
    let size = CGSize(
      width: silhouette.width + (shoulder + GlowMetrics.spread) * 2,
      height: entry.notch.height + GlowMetrics.depth
    )
    entry.glow.silhouette = silhouette
    entry.glow.size = size
    entry.glow.shoulder = shoulder
    entry.glow.cornerRadius = earWidth > 0 ? EarsMetrics.cornerRadius : VortexMetrics.notchCornerRadius
    entry.glowPanel.setFrame(
      CGRect(x: entry.notch.midX - size.width / 2, y: entry.notch.maxY - size.height, width: size.width, height: size.height),
      display: false
    )
  }

  private func indicatorsChanged() {
    let newEars = NotchEars(indicators: indicators)
    if newEars != currentEars {
      currentEars = newEars
      ears.values.forEach(layOut)
      updateMenuBarTitle()
    }
    if let color = NotchEars.flash(indicators, seen: &seenFlashes) {
      flash(color)
    }
  }

  /// Lights the notch up in the color, with a glow that spreads past its edges, then hides the glow again.
  private func flash(_ color: ColorValue) {
    flashGeneration += 1
    let current = flashGeneration
    let isWindowOpen = mainPanel?.isVisible == true
    for entry in ears.values {
      entry.model.flashColor = color
      entry.model.flashes += 1
      entry.glow.color = color
      // Behind the ears, so they stay readable; over the open window, which would hide it.
      if isWindowOpen {
        entry.glowPanel.orderFrontRegardless()
      } else {
        entry.glowPanel.order(.below, relativeTo: entry.panel.windowNumber)
      }
      entry.glow.trigger += 1
    }
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(2))
      guard let self, self.flashGeneration == current else { return }
      self.ears.values.forEach { $0.glowPanel.orderOut(nil) }
    }
  }

  /// When the window closes under the pointer, the notch would report hover at once and open it again.
  /// Tracking starts over, and hover counts only after the pointer has left the notch.
  private func resetNotchHover() {
    let pointer = NSEvent.mouseLocation
    for entry in ears.values {
      if NSMouseInRect(pointer, entry.panel.frame, false) {
        entry.hit.suppressHoverUntilPointerLeaves()
      }
      entry.hit.updateTrackingAreas()
    }
  }

  private func screensChanged() {
    rebuildEars()
    emit(.screensChanged(everyScreenHasNotch: everyScreenHasNotch))
  }

  // MARK: - Menu bar icon

  func setMenuBarIconVisible(_ isVisible: Bool) {
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
      button.action = #selector(menuBarIconPressed)
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
      // Files dropped on the icon: the icon's window takes the drag and hands it to its delegate.
      button.window?.registerForDraggedTypes([.fileURL])
      button.window?.delegate = self
    }
    return item
  }

  func setAcceptsFiles(_ acceptsFiles: Bool) {
    self.acceptsFiles = acceptsFiles
  }

  @objc private func menuBarIconPressed() {
    let event = NSApp.currentEvent
    let isRightClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
    if isRightClick, let item = menuBarItem, let menu = menuBarMenu {
      item.menu = menu
      item.button?.performClick(nil)
      item.menu = nil
    } else {
      emit(.menuBarIconClicked)
    }
  }

  /// Where some display has no notch, the indicators live next to the menu bar icon.
  private func updateMenuBarTitle() {
    guard let button = menuBarItem?.button else { return }
    let text = everyScreenHasNotch ? "" : currentEars.menuBarText
    button.title = text.isEmpty ? "" : " \(text)"
  }
}

// MARK: - Files dropped on the menu bar icon

// NSDraggingDestination makes these visible to the icon's window, which forwards drags to its delegate.
extension WindowController: NSWindowDelegate, NSDraggingDestination {
  func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard acceptsFiles, !Self.fileURLs(in: sender).isEmpty else { return [] }
    menuBarItem?.button?.highlight(true)
    return .copy
  }

  func draggingExited(_ sender: (any NSDraggingInfo)?) {
    menuBarItem?.button?.highlight(false)
  }

  func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    menuBarItem?.button?.highlight(false)
    let urls = Self.fileURLs(in: sender)
    guard acceptsFiles, !urls.isEmpty else { return false }
    emit(.filesDroppedOnMenuBarIcon(urls))
    return true
  }

  private static func fileURLs(in info: any NSDraggingInfo) -> [URL] {
    info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
  }
}
