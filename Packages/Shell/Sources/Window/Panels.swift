import AppKit
import Quartz
import SwiftUI
import VortexCore
import VortexPlatform

/// Borderless panel that floats above the menu bar on every Space without activating the app.
final class VortexPanel: NSPanel {
  var onEscape: (() -> Void)?
  private let acceptsKey: Bool

  /// A panel showing SwiftUI `content` inside the AppKit `root` view.
  convenience init(acceptsKey: Bool, root: NSView, content: some View) {
    let hosting = NSHostingView(rootView: content)
    hosting.sizingOptions = []
    hosting.autoresizingMask = [.width, .height]
    root.addSubview(hosting)
    self.init(acceptsKey: acceptsKey, root: root)
    hosting.frame = root.bounds
  }

  /// A panel showing `root` with whatever it holds already.
  private init(acceptsKey: Bool, root: NSView) {
    self.acceptsKey = acceptsKey
    super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    isFloatingPanel = true
    hidesOnDeactivate = false
    level = .vortex
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    isMovable = false
    isReleasedWhenClosed = false
    animationBehavior = .none
    contentView = root
  }

  /// A new panel set up as this one, holding this one's content view, which this one gives up: the views inside, their
  /// SwiftUI state, their callbacks and the keyboard focus move as they are.
  ///
  /// macOS sometimes keeps a panel that joins all Spaces on one full-screen Space only, until that Space goes: ordered
  /// in from another Space, it shows there, out of sight. Nothing set on the panel brings it back (its collection
  /// behavior, level, ordering out and in), while a new window joins all Spaces again.
  func replacement() -> VortexPanel {
    let focused = focusedView
    let root = contentView ?? NSView()
    contentView = NSView()
    let panel = VortexPanel(acceptsKey: acceptsKey, root: root)
    panel.onEscape = onEscape
    panel.ignoresMouseEvents = ignoresMouseEvents
    panel.hasShadow = hasShadow
    panel.setFrame(frame, display: false)
    if let focused, focused.isDescendant(of: root) {
      panel.makeFirstResponder(focused)
    }
    return panel
  }

  /// The view with the keyboard focus: for a text field being edited, the field rather than its field editor.
  private var focusedView: NSView? {
    if let editor = firstResponder as? NSText, editor.isFieldEditor {
      return editor.delegate as? NSView
    }
    return firstResponder as? NSView
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var canBecomeKey: Bool {
    #if DEBUG
      // A QA run's panels never take the keyboard (VortexPlatform's `QA.allowsKeyWindows`).
      guard QA.allowsKeyWindows else { return false }
    #endif
    return acceptsKey
  }
  override var canBecomeMain: Bool { false }

  override func cancelOperation(_ sender: Any?) {
    onEscape?()
  }

  // Quick Look looks for its controller in the responder chain of the window with keyboard focus,
  // always on the main thread.
  override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
    MainActor.assumeIsolated { QuickLook.shared.hasItems }
  }

  override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
    MainActor.assumeIsolated { QuickLook.shared.beginControl(panel) }
  }

  override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
    MainActor.assumeIsolated { QuickLook.shared.endControl(panel) }
  }

  /// The panel sends the standard editing shortcuts itself, and ⌘Q, which the main menu (`MainMenu`) doesn't have:
  /// AppKit asks the key window before the menu, so a press acts once.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if let action = EditingShortcuts.action(for: event), NSApp.sendAction(action, to: nil, from: self) {
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

/// Reports when the pointer enters or leaves the view; clicks reach the views inside it.
class HoverTrackingView: NSView {
  var onHoverChanged: ((Bool) -> Void)?

  /// What the tracking area reports; a subclass adds what else it needs, such as `.mouseMoved`.
  var trackingOptions: NSTrackingArea.Options {
    [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(rect: .zero, options: trackingOptions, owner: self))
  }

  override func mouseEntered(with event: NSEvent) { onHoverChanged?(true) }
  override func mouseExited(with event: NSEvent) { onHoverChanged?(false) }
}

/// Covers the closed notch: reports hover, where the pointer is, clicks and files dragged onto it. It takes every
/// event inside its bounds, so the SwiftUI content below it stays purely visual.
final class NotchHitView: HoverTrackingView {
  /// A click, with its point in the view.
  var onClick: ((NSPoint) -> Void)?
  /// Where the pointer is, in the view: where it came in, and wherever it moves after that. Silent while hover is
  /// suppressed, so it never leads to an open that hover would not.
  var onPointerMoved: ((NSPoint) -> Void)?
  /// The pointer came in or moved here, even while hover is suppressed: the user is looking at the notch. It opens
  /// nothing.
  var onPointerPresent: (() -> Void)?
  var onFileDragEntered: (() -> Void)?
  private var isHoverSuppressed = false

  override var trackingOptions: NSTrackingArea.Options {
    super.trackingOptions.union(.mouseMoved)
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    // Whatever the shelf takes: files, images and links from browsers, text.
    registerForDraggedTypes([.fileURL, .URL, .png, .tiff, .string])
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
    onPointerPresent?()
    guard !isHoverSuppressed else { return }
    // The point goes first, so the shell knows the ear before the hover can open the window (the delay may be 0).
    onPointerMoved?(convert(event.locationInWindow, from: nil))
    super.mouseEntered(with: event)
  }

  override func mouseMoved(with event: NSEvent) {
    onPointerPresent?()
    guard !isHoverSuppressed else { return }
    onPointerMoved?(convert(event.locationInWindow, from: nil))
  }

  override func mouseExited(with event: NSEvent) {
    isHoverSuppressed = false
    super.mouseExited(with: event)
  }

  override func mouseDown(with event: NSEvent) { onClick?(convert(event.locationInWindow, from: nil)) }

  /// Only a trigger to open the window: what is dragged lands in the tab that takes files, not here.
  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    onFileDragEntered?()
    return []
  }
}
