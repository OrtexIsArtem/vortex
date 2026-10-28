import AppKit
import SwiftUI
import VortexCore

/// A window over all of one display, above everything, the menu bar and the notch included: the frozen screen while a
/// task is captured, or the whole screen of a task. The content finds the display's notch in `\.notchCutout`.
///
/// `show` brings Vortex to the front with it, so the pointer and the keyboard work from the start; `close` gives the
/// front back to the app the user was in, with its keyboard focus. Esc and Return that no field takes go to
/// `onEscape` and `onReturn`.
///
/// `showKeepingFront` leaves the app in front and the keyboard as they are, and the shell keeps its window open
/// meanwhile: the window never takes the keyboard, so nothing hands it on when the window goes, and while it shows,
/// keys pressed in Vortex's window close it (Esc, Return, Space) or go nowhere. So it needs a window of Vortex's with
/// the keyboard: without one it does not show, and once none has it any more it calls `onDismiss`. Clicks reach its
/// buttons only, as in any window without the keyboard; `close` fades it out.
///
/// An app coming to the front calls `onInterrupted` (`onDismiss`) rather than staying hidden under it, also one that
/// came between the moment the screen was taken and `show`: a prompt of the system (Screen Recording's periodic
/// confirmation, a browser's Automation), or the app picked with ⌘Tab.
@MainActor
public final class ScreenOverlay {
  private var panel: OverlayPanel?
  private var activations: (any NSObjectProtocol)?
  /// The app the user was in, which gets the front back.
  private var coveredApp: NSRunningApplication?
  /// Shown by `showKeepingFront`, which holds the shell's window open until `close`.
  private var keepsFront = false
  /// Shown by `showKeepingFront`: takes the keys pressed in Vortex's windows.
  private var keyMonitor: Any?
  /// Shown by `showKeepingFront`: Vortex's windows losing the keyboard.
  private var keyResignations: (any NSObjectProtocol)?

  public init() {}

  public var isShown: Bool { panel != nil }

  /// `over` is the bundle id of the app the user was in when the screen was taken, nil when not known.
  public func show(
    _ content: some View,
    on displayID: CGDirectDisplayID,
    over app: String?,
    onEscape: @escaping @MainActor () -> Void,
    onReturn: @escaping @MainActor () -> Void,
    onInterrupted: @escaping @MainActor () -> Void
  ) {
    // Vortex itself in front is no interruption: the user was in its window. A QA run's front app is simulated.
    let front = Self.isQA ? nil : Self.frontApp()
    guard front == nil || front?.bundleIdentifier == app else {
      // Called once `show` has returned, as it would be for a later interruption.
      Task { @MainActor in onInterrupted() }
      return
    }
    guard let screen = NSScreen.screens.first(where: { $0.displayNumber == displayID }) ?? NSScreen.main else { return }
    stopKeepingFront()
    present(content, on: screen, takesKeyboard: true, onEscape: onEscape, onReturn: onReturn, onInterrupted: onInterrupted)
    guard !Self.isQA else { return }
    coveredApp = front ?? app.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
    NSApp.activate()
  }

  /// QA mode (`QA`): the overlay opens off the displays, never takes the keyboard or the front, and real apps coming to
  /// the front don't interrupt it.
  private static var isQA: Bool {
    #if DEBUG
      QA.isActive
    #else
      false
    #endif
  }

  /// Over the display under the pointer, leaving the app in front where it is.
  public func showKeepingFront(_ content: some View, onDismiss: @escaping @MainActor () -> Void) {
    let pointer = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main
    else { return }
    // Its keys come through the window of Vortex's that has the keyboard; with none, such as when the window closed
    // while the content was made, no key could close it.
    guard NSApp.keyWindow.map({ !($0 is OverlayPanel) }) == true else {
      Task { @MainActor in onDismiss() }
      return
    }
    // Shown the other way: that ends first, with the front given back.
    if isShown, !keepsFront { close() }
    if !keepsFront {
      keepsFront = true
      OutsideActivity.shared.begin()
    }
    coveredApp = nil
    present(content, on: screen, takesKeyboard: false, onEscape: onDismiss, onReturn: onDismiss, onInterrupted: onDismiss)
    stopMonitoringKeys()
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      // Esc, Return, the keypad's Enter and Space.
      if [53, 36, 76, 49].contains(event.keyCode) {
        MainActor.assumeIsolated { onDismiss() }
      }
      return nil
    }
    keyResignations = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification,
      object: nil,
      queue: .main
    ) { _ in
      // A turn later, once the keyboard has moved: to another window of Vortex's, nothing changes.
      Task { @MainActor in
        if NSApp.keyWindow == nil { onDismiss() }
      }
    }
  }

  private func present(
    _ content: some View,
    on screen: NSScreen,
    takesKeyboard: Bool,
    onEscape: @escaping @MainActor () -> Void,
    onReturn: @escaping @MainActor () -> Void,
    onInterrupted: @escaping @MainActor () -> Void
  ) {
    let panel = self.panel ?? OverlayPanel()
    panel.takesKeyboard = takesKeyboard
    panel.onEscape = onEscape
    panel.onReturn = onReturn
    panel.contentView = NSHostingView(rootView: AnyView(content.environment(\.notchCutout, screen.notchInPoints)))
    #if DEBUG
      panel.setFrame(Self.isQA ? QA.offscreen(screen.frame) : screen.frame, display: true)
    #else
      panel.setFrame(screen.frame, display: true)
    #endif
    // In front of everything also while Vortex is not the app in front.
    panel.orderFrontRegardless()
    if takesKeyboard, !Self.isQA { panel.makeKey() }
    self.panel = panel
    stopWatchingActivations()
    guard !Self.isQA else { return }
    activations = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] note in
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
      MainActor.assumeIsolated {
        // Once: another app coming meanwhile changes nothing.
        self?.stopWatchingActivations()
        onInterrupted()
      }
    }
  }

  /// The app in front; nil for Vortex.
  private static func frontApp() -> NSRunningApplication? {
    guard let app = NSWorkspace.shared.frontmostApplication,
          app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else { return nil }
    return app
  }

  private func stopWatchingActivations() {
    if let activations { NSWorkspace.shared.notificationCenter.removeObserver(activations) }
    activations = nil
  }

  private func stopMonitoringKeys() {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
    if let keyResignations { NotificationCenter.default.removeObserver(keyResignations) }
    keyResignations = nil
  }

  /// To `app`, or, when it is gone or unknown, to the app whose window is in front.
  private static func giveFront(to app: NSRunningApplication?) {
    let target = app.flatMap { $0.isTerminated ? nil : $0 } ?? NSRunningApplication.behindVortex()
    target?.activate(from: .current)
  }

  /// The keys go where they went before, and the shell's window may close again.
  private func stopKeepingFront() {
    stopMonitoringKeys()
    guard keepsFront else { return }
    keepsFront = false
    OutsideActivity.shared.end()
  }

  public func close() {
    stopWatchingActivations()
    // The content's pointer, such as a crosshair, would stay until the app under it sets one.
    NSCursor.arrow.set()
    if keepsFront, let panel {
      // Fades, so the screen behind comes back gently, and takes no clicks meanwhile. It is let go once the fade's time
      // is up rather than when the fade reports its end, which with the screen locked may not come.
      panel.ignoresMouseEvents = true
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.15
        panel.animator().alphaValue = 0
      }
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(150))
        panel.orderOut(nil)
        panel.contentView = nil
      }
      self.panel = nil
      stopKeepingFront()
      return
    }
    panel?.orderOut(nil)
    panel?.contentView = nil
    panel = nil
    stopKeepingFront()
    // Still in front, so nothing else took it meanwhile: the app the user was in gets it back.
    if NSApp.isActive {
      Self.giveFront(to: coveredApp)
    }
    coveredApp = nil
  }
}

private final class OverlayPanel: NSPanel {
  var onEscape: @MainActor () -> Void = {}
  var onReturn: @MainActor () -> Void = {}
  /// Whether it may become the window with the keyboard.
  var takesKeyboard = true

  init() {
    super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    // Above the menu bar, the notch window and other apps' menus.
    level = .screenSaver
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    isMovable = false
    acceptsMouseMovedEvents = true
  }

  override var canBecomeKey: Bool { takesKeyboard }
  override var canBecomeMain: Bool { false }

  override func cancelOperation(_ sender: Any?) {
    onEscape()
  }

  /// The app has no main menu, so nothing maps the standard editing shortcuts; the panel sends them itself.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if let action = EditingShortcuts.action(for: event), NSApp.sendAction(action, to: nil, from: self) {
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  override func keyDown(with event: NSEvent) {
    // Return and the keypad's Enter.
    if event.keyCode == 36 || event.keyCode == 76 {
      onReturn()
    } else {
      super.keyDown(with: event)
    }
  }
}
