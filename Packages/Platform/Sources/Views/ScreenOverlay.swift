import AppKit
import SwiftUI

/// A window over all of one display, above everything, the menu bar and the notch included: the frozen screen while a
/// task is captured. Esc and Return that no field takes go to `onEscape` and `onReturn`.
///
/// Vortex comes to the front with it, so the pointer and the keyboard work from the start; `close` gives the front
/// back to the app the user was in, with its keyboard focus.
///
/// An app coming to the front calls `onInterrupted` rather than staying hidden under it, also one that came between
/// the moment the screen was taken and `show`: a prompt of the system (Screen Recording's periodic confirmation, a
/// browser's Automation), or the app picked with ⌘Tab.
@MainActor
public final class ScreenOverlay {
  private var panel: OverlayPanel?
  private var activations: (any NSObjectProtocol)?
  /// The app the user was in, which gets the front back.
  private var coveredApp: NSRunningApplication?

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
    // Vortex itself in front is no interruption: the user was in its window.
    let front = Self.frontApp()
    guard front == nil || front?.bundleIdentifier == app else {
      // Called once `show` has returned, as it would be for a later interruption.
      Task { @MainActor in onInterrupted() }
      return
    }
    guard let screen = NSScreen.screens.first(where: { $0.displayNumber == displayID }) ?? NSScreen.main else { return }
    let panel = self.panel ?? OverlayPanel()
    panel.onEscape = onEscape
    panel.onReturn = onReturn
    panel.contentView = NSHostingView(rootView: AnyView(content))
    panel.setFrame(screen.frame, display: true)
    panel.makeKeyAndOrderFront(nil)
    self.panel = panel
    coveredApp = front ?? app.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
    NSApp.activate()
    stopWatchingActivations()
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

  /// To `app`, or, when it is gone or unknown, to the app whose window is in front.
  private static func giveFront(to app: NSRunningApplication?) {
    let target = app.flatMap { $0.isTerminated ? nil : $0 } ?? NSRunningApplication.behindVortex()
    target?.activate(from: .current)
  }

  public func close() {
    stopWatchingActivations()
    panel?.orderOut(nil)
    panel?.contentView = nil
    panel = nil
    // The content's pointer, such as a crosshair, would stay until the app under it sets one.
    NSCursor.arrow.set()
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

  override var canBecomeKey: Bool { true }
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
