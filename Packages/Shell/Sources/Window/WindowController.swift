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
  /// Sent when the events start and whenever displays change. `anyScreenHasNotch`: some display has one.
  case screensChanged(everyScreenHasNotch: Bool, anyScreenHasNotch: Bool = true)
  /// During keyboard cleaning, a key got past the lock's tap and went down in Vortex, which drops it.
  case keyPressedWhileHeld(KeyboardKey)
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
    /// Where the notch cuts into the content, see `WindowPresentationModel.notch`.
    let notch: CGRect?
    /// The screen the window opens on; nil in a QA run that shows nothing.
    var screen: NSScreen?
  }

  @SharedReader(.notchIndicators) private var allIndicators
  /// Features that don't run: their indicators, left behind as they stopped, don't show (`setHiddenIndicatorOwners`).
  private var hiddenIndicatorOwners: Set<FeatureID> = []
  /// The indicators that show: those of running features, and of keys that are no feature's id.
  private var indicators: [FeatureID: NotchIndicator] {
    allIndicators.filter { !hiddenIndicatorOwners.contains($0.key) }
  }
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
  /// Menus being tracked now, such as a sidebar icon's: the window stays open while one is, as for a drag.
  private var trackedMenus = 0
  private var menuTrackingObservers: [NSObjectProtocol] = []
  private var menuBarItem: NSStatusItem?
  private var menuBarMenu: NSMenu?
  /// Off until the shell applies the user's setting, so a hidden icon never flashes at launch.
  private var isMenuBarIconWanted = false
  /// Whether some feature takes files, so files may be dropped on the menu bar icon.
  private var acceptsFiles = false
  private var outsideClickMonitor: Any?
  /// Drops every key Vortex receives while keyboard cleaning holds the keyboard, telling only which key went down;
  /// nil otherwise.
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
  /// A visible QA run (`--qa-visible`): the ears, the window and the flashes show and animate where plain Vortex puts
  /// them, to record a demo, but the pointer passes through them. As in any run, commands stand for the user.
  private let isQAVisible: Bool
  /// A QA run that shows nothing: the window opens off the displays, without animation (`qaPlacement`).
  private var isOffscreenQA: Bool { isQA && !isQAVisible }
  /// The screen the open window is on, where a change of size places it.
  private var shownScreen: NSScreen?
  /// The last change of size and where the pointer was then, until the pointer moves: a leave it caused isn't one.
  private var lastResize: (kind: WindowSizeRules.Resize, pointer: NSPoint)?
  /// Incremented on every change of size, so a finished animation never acts on a newer one.
  private var resizeGeneration = 0
  /// QA: whether the pretended pointer is inside the window, as it is after opening it from the notch.
  private var isQAPointerInWindow = false
  /// QA: the shell listens for events; until then an event a command makes would be lost.
  private(set) var qaHasEventsSubscriber = false
  /// QA: called once the shell listens for events.
  var qaOnEventsSubscribed: (() -> Void)?
  /// QA: the width the run pretends the notch has (`screens notch=`); nil for this Mac's, or a MacBook Pro's.
  var qaNotchWidth: CGFloat?

  override private init() {
    #if DEBUG
      isQA = QA.isActive
      isQAVisible = QA.isVisible
    #else
      isQA = false
      isQAVisible = false
    #endif
    super.init()
  }

  // MARK: - Setup

  /// Puts the notch on screen and builds the window, so the first open does not wait for it. Call once at launch.
  func install(content: some View, menu: NSMenu) {
    menuBarMenu = menu
    presentation.notch = isOffscreenQA
      ? qaPlacement(for: .click).notch
      : NSScreen.screens.first { $0.notchRect != nil }.flatMap { placement(on: $0).notch }
    presentation.onNotchTapped = { [weak self] in self?.emit(.notchClicked(feature: nil)) }
    mainPanel = makeMainPanel(content: AnyView(content))
    rebuildEars()
    indicatorsObservation = observe { [weak self] in self?.indicatorsChanged() }
    outsideActivityObservation = observe { [weak self] in
      guard let self else { return }
      self.outsideActivityChanged(OutsideActivity.shared.isActive || self.trackedMenus > 0)
    }
    menuTrackingObservers = [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification].map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.trackedMenus = max(0, self.trackedMenus + (name == NSMenu.didBeginTrackingNotification ? 1 : -1))
          self.outsideActivityChanged(OutsideActivity.shared.isActive || self.trackedMenus > 0)
        }
      }
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
    continuation.yield(.screensChanged(everyScreenHasNotch: everyScreenHasNotch, anyScreenHasNotch: anyScreenHasNotch))
    if isQA {
      qaHasEventsSubscriber = true
      qaOnEventsSubscribed?()
    }
    return stream
  }

  private var everyScreenHasNotch: Bool {
    #if DEBUG
      if isQA { return QA.screens.allSatisfy { $0 == .notch } }
    #endif
    return NSScreen.screens.allSatisfy { $0.notchRect != nil }
  }

  private var anyScreenHasNotch: Bool {
    #if DEBUG
      if isQA { return QA.screens.contains(.notch) }
    #endif
    return NSScreen.screens.contains { $0.notchRect != nil }
  }

  // MARK: - Window

  func present(_ reason: OpenReason) {
    guard let shown = mainPanel, let placement = placement(for: reason) else { return }
    seeAlarms()
    generation += 1
    let current = generation

    if isOffscreenQA {
      presentOffscreen(shown, placement)
      return
    }

    if !shown.isVisible { presentation.isExpanded = false }
    presentation.notch = placement.notch
    withoutAnimation { presentation.shownWidth = presentation.contentSize.width }
    shownScreen = placement.screen
    lastResize = nil
    let panel = orderFrontOnActiveSpace(shown, frame: placement.frame)
    // A visible QA run never takes the keyboard either.
    if !reason.isPassing, !isQA { panel.makeKey() }
    panel.contentView?.updateTrackingAreas()
    // NSMouseInRect counts the top edge in, where a pointer pushed against the notch sits.
    let isInside = isQA ? isQAPointerInWindow : NSMouseInRect(NSEvent.mouseLocation, placement.frame, false)
    emit(.pointerInsideWindowChanged(isInside: isInside))
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
    if isOffscreenQA {
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

  // MARK: - Size

  /// Grows or shrinks the open window, keeping its left edge where the screen allows: the content takes its new size at
  /// once, and the window's outline follows with the opening's spring, or at once with Reduce Motion. A closed window
  /// takes the size at its next open. Sizes are in points on the notch the window grows out of.
  func setSize(_ size: WindowSize) {
    guard size != presentation.size else { return }
    let width = size.size(notchWidth: presentation.notch?.width).width
    let grows = width > presentation.contentSize.width
    guard let panel = mainPanel, panel.isVisible else {
      withoutAnimation {
        presentation.size = size
        presentation.shownWidth = width
      }
      return
    }
    let placement: Placement
    if isOffscreenQA {
      placement = qaPlacement(for: presentation.notch == nil ? .hotkey : .click, size: size)
    } else if let screen = shownScreen {
      placement = self.placement(on: screen, size: size)
    } else {
      return
    }
    resizeGeneration += 1
    let current = resizeGeneration
    lastResize = (grows ? .grow : .shrink, NSEvent.mouseLocation)
    // Growing, the window takes its new frame first and the outline widens into it; shrinking, the outline narrows
    // first and the frame follows.
    withoutAnimation { presentation.size = size }
    if grows || isOffscreenQA {
      presentation.notch = placement.notch
      panel.setFrame(placement.frame, display: true)
    }
    let finish = { [weak self] in
      guard let self, self.resizeGeneration == current, !grows, !self.isOffscreenQA else { return }
      self.presentation.notch = placement.notch
      panel.setFrame(placement.frame, display: true)
      panel.contentView?.updateTrackingAreas()
    }
    if isOffscreenQA || reduceMotion {
      withoutAnimation { presentation.shownWidth = width }
      finish()
    } else {
      withAnimation(openAnimation) {
        presentation.shownWidth = width
      } completion: {
        finish()
      }
    }
    panel.contentView?.updateTrackingAreas()
  }

  /// The pointer came into the window or left it. A leave right after the window shrank away from a still pointer
  /// isn't one (`WindowSizeRules`).
  private func pointerHoverChanged(_ isInside: Bool) {
    let resize = lastResize
    let moved = resize.map { NSEvent.mouseLocation != $0.pointer } ?? true
    if moved { lastResize = nil }
    guard isInside || WindowSizeRules.closesOnPointerLeave(after: resize?.kind, pointerMoved: moved) else { return }
    emit(.pointerInsideWindowChanged(isInside: isInside))
  }

  // MARK: - Indicators

  /// Hides the indicators of features that don't run, and shows those of features that run again.
  func setHiddenIndicatorOwners(_ owners: Set<FeatureID>) {
    guard owners != hiddenIndicatorOwners else { return }
    hiddenIndicatorOwners = owners
    indicatorsChanged()
  }

  // MARK: - Keyboard cleaning

  /// While held, Vortex is the app in front, its window has the keyboard and every key that reaches Vortex is dropped.
  /// So a key that passes the lock's tap — while some app has secure input on, or for the moment macOS turns the tap
  /// off — goes nowhere rather than into the app the user was in; the lock screen still washes it. Let go, that app
  /// gets the front and the keys back, unless the user went to another app meanwhile.
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
      keyboardHoldMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
        if let key = event.cgEvent.flatMap(KeyboardKey.init(pressedBy:)) {
          MainActor.assumeIsolated { WindowController.shared.emit(.keyPressedWhileHeld(key)) }
        }
        return nil
      }
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
      self?.pointerHoverChanged(isInside)
    }
    let panel = VortexPanel(acceptsKey: true, root: root, content: WindowChromeView(model: presentation, content: content))
    panel.onEscape = { [weak self] in self?.emit(.escapePressed) }
    // A visible QA run shows the window, but the user's pointer passes through it.
    panel.ignoresMouseEvents = isQAVisible
    // Lay the content out once while hidden, so opening only has to animate it.
    let shoulder = presentation.notch == nil ? 0 : VortexMetrics.shoulder
    let size = presentation.contentSize
    panel.setFrame(CGRect(x: 0, y: 0, width: size.width + shoulder * 2, height: size.height), display: false)
    root.layoutSubtreeIfNeeded()
    return panel
  }

  /// Orders the window in at `frame`, without a shadow. Stuck on another Space (`VortexPanel.replacement`), it would
  /// open there, out of sight, and every hover after would find it open: a new window takes its content and opens here.
  private func orderFrontOnActiveSpace(_ shown: VortexPanel, frame: CGRect) -> VortexPanel {
    shown.hasShadow = false
    shown.setFrame(frame, display: true)
    shown.orderFrontRegardless()
    guard !shown.isOnActiveSpace else { return shown }
    let wasKey = shown.isKeyWindow
    let panel = shown.replacement()
    // Closed rather than ordered out, so the window server takes it off its Space as well.
    shown.close()
    mainPanel = panel
    panel.orderFrontRegardless()
    if wasKey { panel.makeKey() }
    return panel
  }

  private func placement(for reason: OpenReason) -> Placement? {
    if isOffscreenQA { return qaPlacement(for: reason) }
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
    return placement(on: screen)
  }

  /// Where the window goes on the screen: out of its notch, or under the menu bar icon on a screen without one.
  private func placement(on screen: NSScreen, size: WindowSize? = nil) -> Placement {
    let size = size ?? presentation.size
    if let notch = screen.notchRect {
      let frame = ScreenGeometry.notchWindowFrame(
        notch: notch,
        screenFrame: screen.frame,
        visibleFrame: screen.visibleFrame,
        size: size,
        shoulder: VortexMetrics.shoulder
      )
      return Placement(
        frame: frame,
        notch: ScreenGeometry.notchCutout(notch: notch, windowFrame: frame, shoulder: VortexMetrics.shoulder),
        screen: screen
      )
    }
    let iconFrame = menuBarItem?.button?.window.flatMap { $0.screen == screen ? $0.frame : nil }
    let anchor = iconFrame ?? CGRect(x: screen.visibleFrame.maxX - 60, y: screen.visibleFrame.maxY, width: 1, height: 1)
    return Placement(
      frame: ScreenGeometry.menuBarWindowFrame(anchor: anchor, visibleFrame: screen.visibleFrame, size: size),
      notch: nil,
      screen: screen
    )
  }

  /// QA: where the window would open on the displays the run pretends to have, moved off the real ones. The pointer
  /// is on the main display, at its notch when it has one; the menu bar icon is there too.
  private func qaPlacement(for reason: OpenReason, size: WindowSize? = nil) -> Placement {
    #if DEBUG
      let screens = QA.screens
      let screen: QALaunch.Screen? = switch reason {
      case .hover, .click, .fileDrag: screens.contains(.notch) ? .notch : screens.first
      case .hotkey, .menuBarIcon: screens.first
      }
      let size = size ?? presentation.size
      if screen == .notch {
        let notch = qaNotchSize
        let content = size.size(notchWidth: notch.width)
        let frame = CGRect(x: 0, y: 0, width: content.width + VortexMetrics.shoulder * 2, height: content.height)
        // The notch stays in the middle of the regular window, which the large one keeps the left edge of.
        let x = (WindowSize.regular.size(notchWidth: notch.width).width - notch.width) / 2
        return Placement(frame: QA.offscreen(frame), notch: CGRect(x: x, y: 0, width: notch.width, height: notch.height))
      }
      return Placement(frame: QA.offscreen(CGRect(origin: .zero, size: size.size)), notch: nil)
    #else
      return Placement(frame: .zero, notch: nil)
    #endif
  }

  /// QA: opens at once, off the displays, without taking the keyboard: a panel made key takes the keys of the app the
  /// user types in even while Vortex is not in front.
  private func presentOffscreen(_ panel: VortexPanel, _ placement: Placement) {
    presentation.notch = placement.notch
    withoutAnimation { presentation.shownWidth = presentation.contentSize.width }
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
    // A QA run shows no ears, unless it is a visible one: its indicators are in the state dump.
    for screen in NSScreen.screens where !isOffscreenQA {
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
      // A visible QA run draws the ears, but the user's pointer passes through them.
      entry.panel.ignoresMouseEvents = isQAVisible
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
    emit(.screensChanged(everyScreenHasNotch: everyScreenHasNotch, anyScreenHasNotch: anyScreenHasNotch))
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

  /// The window `snapshot window=ears` draws the closed notch in, made at its first snapshot.
  @MainActor private var qaEarsSnapshot: NSWindow?

  /// What the shell's QA commands drive: the events the user would make at the notch, the menu bar icon and the window.
  extension WindowController {
    func qaEmit(_ event: WindowEvent) {
      emit(event)
    }

    var qaPanel: NSWindow? { mainPanel }
    var qaMenu: NSMenu? { menuBarMenu }

    /// The notch on a display the run pretends has one: this Mac's, or a MacBook Pro's, as wide as `screens notch=` says.
    var qaNotchSize: CGSize {
      CGSize(width: qaNotchWidth ?? QA.notchSize.width, height: QA.notchSize.height)
    }

    /// The window's content as it is laid out now, in points: wider on a wide notch.
    var qaContentSize: CGSize { presentation.contentSize }

    /// The closed notch with the ears the run's indicators make now, at the notch size the run pretends, in a window
    /// of its own that is never ordered in: a QA run draws no ears, so `snapshot window=ears` draws them here.
    func qaEarsWindow() -> NSWindow {
      let model = EarsModel()
      model.notchSize = qaNotchSize
      model.ears = currentEars
      model.earWidth = EarsMetrics.earWidth(for: currentEars)
      let shoulder = model.earWidth > 0 ? VortexMetrics.shoulder : 0
      let size = CGSize(width: model.notchSize.width + (model.earWidth + shoulder) * 2, height: model.notchSize.height)
      let window = qaEarsSnapshot ?? {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        qaEarsSnapshot = window
        return window
      }()
      window.contentView = NSHostingView(rootView: NotchEarsView(model: model).frame(width: size.width, height: size.height))
      window.setFrame(QA.offscreen(CGRect(origin: .zero, size: size)), display: false)
      return window
    }
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
      emit(.screensChanged(everyScreenHasNotch: everyScreenHasNotch, anyScreenHasNotch: anyScreenHasNotch))
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
