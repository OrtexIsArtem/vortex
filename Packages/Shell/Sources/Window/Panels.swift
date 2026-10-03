import AppKit
import SwiftUI

/// Borderless panel that floats above the menu bar on every Space without activating the app.
final class VortexPanel: NSPanel {
  var onEscape: (() -> Void)?
  private let acceptsKey: Bool

  /// A panel showing SwiftUI `content` inside the AppKit `root` view.
  init(acceptsKey: Bool, root: NSView, content: some View) {
    self.acceptsKey = acceptsKey
    super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    isFloatingPanel = true
    hidesOnDeactivate = false
    level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    isMovable = false
    isReleasedWhenClosed = false
    animationBehavior = .none

    let hosting = NSHostingView(rootView: content)
    hosting.sizingOptions = []
    hosting.autoresizingMask = [.width, .height]
    root.addSubview(hosting)
    contentView = root
    hosting.frame = root.bounds
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var canBecomeKey: Bool { acceptsKey }
  override var canBecomeMain: Bool { false }

  override func cancelOperation(_ sender: Any?) {
    onEscape?()
  }

  /// The app has no main menu, so nothing maps the standard editing shortcuts; the panel sends them itself.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if let action = Self.standardAction(for: event), NSApp.sendAction(action, to: nil, from: self) {
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  private static func standardAction(for event: NSEvent) -> Selector? {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let isShifted = flags == [.command, .shift]
    guard flags == .command || isShifted else { return nil }
    switch (event.charactersIgnoringModifiers?.lowercased(), isShifted) {
    case ("x", false): return #selector(NSText.cut(_:))
    case ("c", false): return #selector(NSText.copy(_:))
    case ("v", false): return #selector(NSText.paste(_:))
    case ("a", false): return #selector(NSText.selectAll(_:))
    case ("z", false): return Selector(("undo:"))
    case ("z", true): return Selector(("redo:"))
    case ("q", false): return #selector(NSApplication.terminate(_:))
    default: return nil
    }
  }
}

/// Reports when the pointer enters or leaves the view; clicks reach the views inside it.
class HoverTrackingView: NSView {
  var onHoverChanged: ((Bool) -> Void)?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
  }

  override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
  override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
}

/// Covers the closed notch: reports hover, clicks and files dragged onto it. It takes every event inside
/// its bounds, so the SwiftUI content below it stays purely visual.
final class NotchHitView: HoverTrackingView {
  var onClick: (() -> Void)?
  var onFileDragEntered: (() -> Void)?
  private var isHoverSuppressed = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    registerForDraggedTypes([.fileURL])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// After the window closes under the pointer, hovering counts again only once the pointer has left the notch.
  func suppressHoverUntilPointerLeaves() {
    isHoverSuppressed = true
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    // The default test counts the top edge in, where a pointer pushed against the notch sits.
    super.hitTest(point) == nil ? nil : self
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func mouseEntered(with event: NSEvent) {
    guard !isHoverSuppressed else { return }
    super.mouseEntered(with: event)
  }

  override func mouseExited(with event: NSEvent) {
    isHoverSuppressed = false
    super.mouseExited(with: event)
  }

  override func mouseDown(with event: NSEvent) { onClick?() }

  /// Only a trigger to open the window: the files land in the tab that takes them, not here.
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    onFileDragEntered?()
    return []
  }
}
