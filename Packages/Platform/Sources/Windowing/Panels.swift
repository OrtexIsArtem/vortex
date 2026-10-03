import AppKit

/// Borderless panel that floats above the menu bar on every Space without activating the app.
final class VortexPanel: NSPanel {
  var onEscape: (() -> Void)?
  private let acceptsKey: Bool

  init(acceptsKey: Bool) {
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
  }

  override var canBecomeKey: Bool { acceptsKey }
  override var canBecomeMain: Bool { false }

  override func cancelOperation(_ sender: Any?) {
    onEscape?()
  }
}

/// Covers the closed notch: reports hover, clicks and files dragged onto it.
/// It swallows every event inside its bounds, so the SwiftUI content below it stays purely visual.
final class NotchHitView: NSView {
  var onHoverChanged: ((Bool) -> Void)?
  var onClick: (() -> Void)?
  var onFileDragEntered: (() -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    registerForDraggedTypes([.fileURL])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func hitTest(_ point: NSPoint) -> NSView? {
    frame.contains(point) ? self : nil
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
  }

  override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
  override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
  override func mouseDown(with event: NSEvent) { onClick?() }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    onFileDragEntered?()
    return .copy
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { false }
}

/// Root of the window: reports when the pointer enters or leaves it, while clicks reach the content.
final class PointerTrackingView: NSView {
  var onPointerInsideChanged: ((Bool) -> Void)?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
  }

  override func mouseEntered(with event: NSEvent) { onPointerInsideChanged?(true) }
  override func mouseExited(with event: NSEvent) { onPointerInsideChanged?(false) }
}

/// Transparent layer over the menu bar button that accepts dropped files and passes clicks to the button.
final class FileDropView: NSView {
  var onDrop: (([URL]) -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    registerForDraggedTypes([.fileURL])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func mouseDown(with event: NSEvent) { superview?.mouseDown(with: event) }
  override func rightMouseDown(with event: NSEvent) { superview?.rightMouseDown(with: event) }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let urls = sender.draggingPasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] ?? []
    guard !urls.isEmpty else { return false }
    onDrop?(urls)
    return true
  }
}
