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
  /// The ear under the pointer changed: `feature` owns the ear it is over, nil on the cutout. Sent when the pointer
  /// comes in over an ear (before its `notchHoverChanged`) and whenever the ear under it changes after that. Leaving
  /// the notch resets it to nil without an event of its own: `notchHoverChanged(isInside: false)` says so.
  case notchPointerOver(feature: FeatureID?)
  /// A click on the closed notch or on the notch of the open window; `feature` owns the ear clicked, nil on the cutout.
  case notchClicked(feature: FeatureID?)
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
  /// The feature whose ear the pointer is over, as the shell last heard it: nil on the cutout and while the pointer is
  /// away. A move is reported only when this changes; it starts over when the pointer leaves the notch, as in the shell.
  private var pointerEar: FeatureID?
  /// The last flash number seen per feature, see `NotchEars.flash`.
  private var seenFlashes: [FeatureID: Int] = [:]
  /// Incremented on every flash, so an older flash never hides the glow of a newer one.
  private var flashGeneration = 0
  /// The last alarm number seen per feature, see `NotchEars.unseenAlarm`.
  private var seenAlarms: [FeatureID: Int] = [:]
  /// Flashes the notch while an alarm is unseen; nil while none flashes.
  private var alarmTask: Task<Void, Never>?
  private static let alarmFlashesWithWindowOpen = 3
  private var indicatorsObservation: ObserveToken?
  private var outsideActivityObservation: ObserveToken?
  private var menuBarItem: NSStatusItem?
  private var menuBarMenu: NSMenu?
  /// Off until the shell applies the user's setting, so a hidden icon never flashes at launch.
  private var isMenuBarIconWanted = false
  /// Whether some feature takes files, so files may be dropped on the menu bar icon.
  private var acceptsFiles = false
  private var outsideClickMonitor: Any?
  /// Drops every key Vortex receives while keyboard cleaning holds the keyboard; nil otherwise.
  private var keyboardHoldMonitor: Any?
  /// The app that was in front when keyboard cleaning brought Vortex there; it gets the front back after.
  private var appBeforeKeyboardHold: NSRunningApplication?
  private var screenObserver: NSObjectProtocol?
  /// Incremented on every present and dismiss, so a finished animation never acts on a newer one.
  private var generation = 0
  private var emit: (WindowEvent) -> Void = { _ in }
  private var finishEvents: () -> Void = {}
  /// QA mode (VortexPlatform's `QA`): nothing on screen. No ears, no menu bar icon, no monitors; the window opens off
  /// the displays without animation and never takes the keyboard; the displays are the ones the run pretends to have.
  private let isQA: Bool
  /// QA: whether the pretended pointer is inside the window, as it is after opening it from the notch.
  private var isQAPointerInWindow = false

  override private init() {
    #if DEBUG
      isQA = QA.isActive
    #else
      isQA = false
    #endif
    super.init()
  }

  // MARK: - Setup

  /// Puts the notch on screen and builds the window, so the first open does not wait for it. Call once at launch.
  func install(content: some View, menu: NSMenu) {
    menuBarMenu = menu
    presentation.notch = isQA ? qaPlacement(for: .click).notch : NSScreen.screens.lazy.compactMap(\.notchRect).first?.size
    presentation.onNotchTapped = { [weak self] in self?.emit(.notchClicked(feature: nil)) }
    mainPanel = makeMainPanel(content: AnyView(content))
    rebuildEars()
    indicatorsObservation = observe { [weak self] in self?.indicatorsChanged() }
    outsideActivityObservation = observe { [weak self] in
      self?.outsideActivityChanged(OutsideActivity.shared.isActive)
    }
    // A QA run's displays change only by command.
    guard !isQA else { return }
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
    #if DEBUG
      if isQA { return QA.screens.allSatisfy { $0 == .notch } }
    #endif
    return NSScreen.screens.allSatisfy { $0.notchRect != nil }
  }

  // MARK: - Window

  func present(_ reason: OpenReason) {
    guard let panel = mainPanel, let placement = placement(for: reason) else { return }
    seeAlarms()
    generation += 1
    let current = generation

    if isQA {
      presentOffscreen(panel, placement)
      return
    }

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
        // Out of the notch the window has no shadow: macOS draws a light rim along a window's shadow, which shows
        // as a strip between the window and the top of the screen. Under the menu bar icon the shadow lifts it.
        guard let self, self.generation == current, placement.notch == nil else { return }
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
    if isQA {
      withoutAnimation { presentation.isExpanded = false }
      panel.orderOut(nil)
      return
    }
    panel.hasShadow = false
    withAnimation(closeAnimation) {
      presentation.isExpanded = false
    } completion: { [weak self] in
      guard let self, self.generation == current else { return }
      panel.orderOut(nil)
      self.resetNotchHover()
    }
  }

  // MARK: - Keyboard cleaning

  /// While held, Vortex is the app in front, its window has the keyboard and every key that reaches Vortex is dropped.
  /// So a key that passes the lock's tap — while some app has secure input on, or for the moment macOS turns the tap
  /// off — goes nowhere rather than into the app the user was in. Let go, that app gets the front and the keys back,
  /// unless the user went to another app meanwhile.
  func holdKeyboard(_ isHeld: Bool) {
    if isQA {
      // Never in front and never the keyboard: the lock itself is simulated.
      #if DEBUG
        QA.log("window", "holdKeyboard", ["held": "\(isHeld)"])
      #endif
      return
    }
    if isHeld {
      guard keyboardHoldMonitor == nil else { return }
      if let front = NSWorkspace.shared.frontmostApplication, front != .current {
        appBeforeKeyboardHold = front
      }
      keyboardHoldMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { _ in nil }
      NSApp.activate()
      mainPanel?.makeKey()
    } else if let monitor = keyboardHoldMonitor {
      NSEvent.removeMonitor(monitor)
      keyboardHoldMonitor = nil
      if NSApp.isActive, let app = appBeforeKeyboardHold, !app.isTerminated {
        app.activate(from: .current)
      }
      appBeforeKeyboardHold = nil
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
    if isQA { return qaPlacement(for: reason) }
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

  /// QA: where the window would open on the displays the run pretends to have, moved off the real ones. The pointer
  /// is on the main display, at its notch when it has one; the menu bar icon is there too.
  private func qaPlacement(for reason: OpenReason) -> Placement {
    #if DEBUG
      let screens = QA.screens
      let screen: QALaunch.Screen? = switch reason {
      case .hover, .click, .fileDrag: screens.contains(.notch) ? .notch : screens.first
      case .hotkey, .menuBarIcon: screens.first
      }
      let size = VortexMetrics.windowSize
      if screen == .notch {
        let frame = CGRect(x: 0, y: 0, width: size.width + VortexMetrics.shoulder * 2, height: size.height)
        return Placement(frame: QA.offscreen(frame), notch: QA.notchSize)
      }
      return Placement(frame: QA.offscreen(CGRect(origin: .zero, size: size)), notch: nil)
    #else
      return Placement(frame: .zero, notch: nil)
    #endif
  }

  /// QA: opens at once, off the displays, without taking the keyboard: a panel made key takes the keys of the app the
  /// user types in even while Vortex is not in front.
  private func presentOffscreen(_ panel: VortexPanel, _ placement: Placement) {
    presentation.notch = placement.notch
    panel.hasShadow = false
    panel.setFrame(placement.frame, display: true)
    panel.orderFrontRegardless()
    emit(.pointerInsideWindowChanged(isInside: isQAPointerInWindow))
    withoutAnimation { presentation.isExpanded = true }
  }

  private func withoutAnimation(_ change: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, change)
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
      let isInside = isQA ? isQAPointerInWindow : NSMouseInRect(NSEvent.mouseLocation, panel.frame, false)
      emit(.pointerInsideWindowChanged(isInside: isInside))
    }
  }

  // MARK: - Outside clicks

  private func installOutsideClickMonitor() {
    // QA watches no clicks: `entry kind=outside` stands for one.
    guard !isQA, outsideClickMonitor == nil else { return }
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
    // A QA run shows no ears: its indicators are in the state dump.
    for screen in NSScreen.screens where !isQA {
      guard let notch = screen.notchRect else { continue }
      let model = EarsModel()
      model.notchSize = notch.size
      let hit = NotchHitView()
      hit.onHoverChanged = { [weak self] isInside in
        // The shell forgets the ear when the pointer leaves, so this does too.
        if !isInside { self?.pointerEar = nil }
        self?.emit(.notchHoverChanged(isInside: isInside))
      }
      hit.onPointerPresent = { [weak self] in self?.seeAlarms() }
      hit.onPointerMoved = { [weak self, weak hit] point in
        guard let self, let hit else { return }
        self.pointerMoved(over: self.currentEars.feature(atX: point.x, width: hit.bounds.width, notchWidth: notch.width))
      }
      hit.onClick = { [weak self, weak hit] point in
        guard let self, let hit else { return }
        let feature = self.currentEars.feature(atX: point.x, width: hit.bounds.width, notchWidth: notch.width)
        self.emit(.notchClicked(feature: feature))
      }
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

  /// Tells the shell which ear the pointer is over, only when that changes: hovering opens the ear's feature.
  private func pointerMoved(over feature: FeatureID?) {
    guard feature != pointerEar else { return }
    pointerEar = feature
    emit(.notchPointerOver(feature: feature))
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
      // The countdown changes every second; the panels change size only when the ears get wider or narrower.
      let isResized = EarsMetrics.earWidth(for: newEars) != EarsMetrics.earWidth(for: currentEars)
      currentEars = newEars
      if isResized {
        ears.values.forEach(layOut)
      } else {
        ears.values.forEach { $0.model.ears = newEars }
      }
      updateMenuBarTitle()
    }
    if let color = NotchEars.flash(indicators, seen: &seenFlashes) {
      flash(color)
    }
    startAlarmIfUnseen()
  }

  /// Flashes the notch, one flash after another, while an alarm is unseen. With the window open the user is at Vortex
  /// already: a few flashes say it, and it counts as seen. Without a notch on any screen the alarm waits for one.
  private func startAlarmIfUnseen() {
    guard alarmTask == nil, !ears.isEmpty, NotchEars.unseenAlarm(indicators, seen: seenAlarms) != nil else { return }
    alarmTask = Task { @MainActor [weak self] in
      var flashesWithWindowOpen = 0
      while !Task.isCancelled {
        guard let self else { return }
        // Not cancelled, so this is the current alarm task: `seeAlarms` cancels a task as it lets it go.
        guard let color = NotchEars.unseenAlarm(self.indicators, seen: self.seenAlarms), !self.ears.isEmpty else {
          self.alarmTask = nil
          return
        }
        if flashesWithWindowOpen >= Self.alarmFlashesWithWindowOpen {
          self.seeAlarms()
          return
        }
        self.flash(color)
        if self.mainPanel?.isVisible == true { flashesWithWindowOpen += 1 }
        try? await Task.sleep(for: GlowMetrics.flashDuration)
      }
    }
  }

  /// The user has seen the alarms showing now: the pointer is over the notch, or the window opened.
  private func seeAlarms() {
    NotchEars.seeAlarms(indicators, seen: &seenAlarms)
    alarmTask?.cancel()
    alarmTask = nil
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
    // An alarm that waited for a notch flashes on the one that came back.
    startAlarmIfUnseen()
    emit(.screensChanged(everyScreenHasNotch: everyScreenHasNotch))
  }

  // MARK: - Menu bar icon

  func setMenuBarIconVisible(_ isVisible: Bool) {
    isMenuBarIconWanted = isVisible
    updateMenuBarIcon()
  }

  private func updateMenuBarIcon() {
    // A QA run puts no icon in the menu bar; the state says whether it would.
    guard !isQA else { return }
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
      // The title is the timer's time and changes every second: equal-width digits keep the item, and the icons to its
      // left, from shifting.
      button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)
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

#if DEBUG
  // MARK: - QA mode

  /// What the shell's QA commands drive: the events the user would make at the notch, the menu bar icon and the window.
  extension WindowController {
    func qaEmit(_ event: WindowEvent) {
      emit(event)
    }

    var qaPanel: NSWindow? { mainPanel }
    var qaMenu: NSMenu? { menuBarMenu }
    /// Whether the menu bar icon would show: QA puts none in the menu bar.
    var qaIsMenuBarIconShown: Bool { isMenuBarIconWanted }
    var qaEars: NotchEars { currentEars }
    var qaIsPointerInWindow: Bool { isQAPointerInWindow }

    /// Where the pretended pointer is: inside the window, or not; the window hears of it when it is open.
    func qaMovePointer(intoWindow isInside: Bool) {
      isQAPointerInWindow = isInside
      if mainPanel?.isVisible == true {
        emit(.pointerInsideWindowChanged(isInside: isInside))
      }
    }

    /// The pretended displays changed, as when one is connected or disconnected.
    func qaScreensChanged() {
      emit(.screensChanged(everyScreenHasNotch: everyScreenHasNotch))
    }
  }
#endif

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
