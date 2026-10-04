import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// What a dragged item becomes in the app it is dropped on.
public enum DragItem: Equatable, Sendable {
  case text(String)
  case link(URL)
  case file(URL)
}

/// Whether something is being dragged out of a Vortex window. The shell keeps the window open meanwhile.
@MainActor
@Observable
public final class DragSessions {
  public static let shared = DragSessions()
  public private(set) var isDragging = false

  nonisolated init() {}

  fileprivate func setDragging(_ isDragging: Bool) {
    self.isDragging = isDragging
  }
}

/// A click on a `DragSourceArea`.
public struct DragSourceClick: Equatable, Sendable {
  public var count: Int
  public var modifiers: EventModifiers

  public init(count: Int, modifiers: EventModifiers) {
    self.count = count
    self.modifiers = modifiers
  }
}

/// The surface of something the user clicks and drags out of Vortex: a clipboard card, a shelf file.
///
/// Lay it over the item's content, under its buttons. It reports hover and clicks, and drags `items()` into other
/// apps, several at once if needed, telling `DragSessions` when a drag starts and ends. Right clicks go through to
/// the content, so a SwiftUI `contextMenu` on it still works. AppKit-backed: a SwiftUI drag carries one item and
/// never says when it ends.
public struct DragSourceArea: NSViewRepresentable {
  private let items: @MainActor () -> [DragItem]
  private let onClick: @MainActor (DragSourceClick) -> Void
  private let onHover: @MainActor (Bool) -> Void

  public init(
    items: @escaping @MainActor () -> [DragItem],
    onClick: @escaping @MainActor (DragSourceClick) -> Void = { _ in },
    onHover: @escaping @MainActor (Bool) -> Void = { _ in }
  ) {
    self.items = items
    self.onClick = onClick
    self.onHover = onHover
  }

  public func makeNSView(context: Context) -> DragSourceView {
    let view = DragSourceView()
    updateNSView(view, context: context)
    return view
  }

  public func updateNSView(_ view: DragSourceView, context: Context) {
    view.items = items
    view.onClick = onClick
    view.onHover = onHover
  }
}

public final class DragSourceView: NSView, NSDraggingSource {
  fileprivate var items: @MainActor () -> [DragItem] = { [] }
  fileprivate var onClick: @MainActor (DragSourceClick) -> Void = { _ in }
  fileprivate var onHover: @MainActor (Bool) -> Void = { _ in }
  private var mouseDown: NSEvent?
  /// A drag starts once the pointer has moved this far with the button down.
  private let dragThreshold: CGFloat = 4

  override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override public func hitTest(_ point: NSPoint) -> NSView? {
    let event = NSApp.currentEvent
    let isContextClick = event?.type == .rightMouseDown
      || (event?.type == .leftMouseDown && event?.modifierFlags.contains(.control) == true)
    return isContextClick ? nil : super.hitTest(point)
  }

  override public func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
  }

  override public func mouseEntered(with event: NSEvent) { onHover(true) }
  override public func mouseExited(with event: NSEvent) { onHover(false) }

  override public func mouseDown(with event: NSEvent) {
    mouseDown = event
  }

  override public func mouseDragged(with event: NSEvent) {
    guard let mouseDown else { return }
    let start = mouseDown.locationInWindow
    let distance = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
    guard distance >= dragThreshold else { return }
    self.mouseDown = nil
    let items = items()
    guard !items.isEmpty else { return }
    beginDrag(items, with: mouseDown)
  }

  override public func mouseUp(with event: NSEvent) {
    guard mouseDown != nil else { return }
    mouseDown = nil
    onClick(DragSourceClick(count: event.clickCount, modifiers: EventModifiers(event.modifierFlags)))
  }

  private func beginDrag(_ items: [DragItem], with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    let draggingItems = items.enumerated().map { index, item in
      let image = item.dragImage
      let offset = CGFloat(min(index, 4)) * 6
      let frame = CGRect(
        x: location.x - image.size.width / 2 + offset,
        y: location.y - image.size.height / 2 - offset,
        width: image.size.width,
        height: image.size.height
      )
      let draggingItem = NSDraggingItem(pasteboardWriter: item.pasteboardWriter)
      draggingItem.setDraggingFrame(frame, contents: image)
      return draggingItem
    }
    let session = beginDraggingSession(with: draggingItems, event: event, source: self)
    session.animatesToStartingPositionsOnCancelOrFail = true
  }

  public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    // Copy, never move: the shelf and the clipboard keep what was dragged out of them.
    .copy
  }

  public func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
    DragSessions.shared.setDragging(true)
  }

  public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
    DragSessions.shared.setDragging(false)
  }
}

extension DragItem {
  @MainActor
  fileprivate var pasteboardWriter: any NSPasteboardWriting {
    switch self {
    case let .text(text): text as NSString
    case let .link(url): url as NSURL
    case let .file(url): url as NSURL
    }
  }

  @MainActor
  fileprivate var dragImage: NSImage {
    let icon: NSImage
    switch self {
    case .text:
      icon = NSWorkspace.shared.icon(for: .plainText)
    case .link:
      icon = NSWorkspace.shared.icon(for: .internetShortcut)
    case let .file(url):
      icon = Self.preview(ofImageAt: url) ?? NSWorkspace.shared.icon(forFile: url.path)
    }
    // A copy: the workspace may hand out shared images.
    let image = icon.copy() as? NSImage ?? icon
    let side: CGFloat = 56
    let scale = min(side / max(image.size.width, 1), side / max(image.size.height, 1))
    image.size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    return image
  }

  /// The picture itself for image files small enough to read at once.
  @MainActor
  private static func preview(ofImageAt url: URL) -> NSImage? {
    guard let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey]),
          values.contentType?.conforms(to: .image) == true, (values.fileSize ?? .max) < 20_000_000
    else { return nil }
    return NSImage(contentsOf: url)
  }
}

extension EventModifiers {
  init(_ flags: NSEvent.ModifierFlags) {
    self = []
    if flags.contains(.command) { insert(.command) }
    if flags.contains(.shift) { insert(.shift) }
    if flags.contains(.option) { insert(.option) }
    if flags.contains(.control) { insert(.control) }
  }
}
