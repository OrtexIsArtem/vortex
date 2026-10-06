import AppKit
import SwiftUI

/// A window over all of one display, above everything, the menu bar and the notch included: the frozen screen while a
/// task is captured. It takes the keyboard without bringing Vortex to the front, so the app the user was in stays the
/// active one. Esc and Return that no field takes go to `onEscape` and `onReturn`.
@MainActor
public final class ScreenOverlay {
  private var panel: OverlayPanel?

  public init() {}

  public var isShown: Bool { panel != nil }

  public func show(
    _ content: some View,
    on displayID: CGDirectDisplayID,
    onEscape: @escaping @MainActor () -> Void,
    onReturn: @escaping @MainActor () -> Void
  ) {
    guard let screen = NSScreen.screens.first(where: { $0.displayNumber == displayID }) ?? NSScreen.main else { return }
    let panel = self.panel ?? OverlayPanel()
    panel.onEscape = onEscape
    panel.onReturn = onReturn
    let host = OverlayHostingView(rootView: AnyView(content))
    host.cursor = cursor
    panel.contentView = host
    panel.setFrame(screen.frame, display: true)
    panel.makeKeyAndOrderFront(nil)
    self.panel = panel
  }

  /// The pointer over the whole overlay, such as a crosshair while a frame is drawn; nil leaves it to the content.
  public var cursor: NSCursor? {
    didSet {
      guard cursor !== oldValue, let host = panel?.contentView as? OverlayHostingView else { return }
      host.cursor = cursor
      panel?.invalidateCursorRects(for: host)
    }
  }

  public func close() {
    panel?.orderOut(nil)
    panel?.contentView = nil
    panel = nil
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

private final class OverlayHostingView: NSHostingView<AnyView> {
  var cursor: NSCursor?

  override func resetCursorRects() {
    super.resetCursorRects()
    if let cursor { addCursorRect(bounds, cursor: cursor) }
  }
}
