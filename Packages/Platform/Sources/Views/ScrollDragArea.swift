import AppKit
import SwiftUI

/// What happens on a `ScrollDragArea`. Points are in the area's own coordinates, from its top left corner.
public enum ScrollDragEvent: Equatable, Sendable {
  /// Two fingers on the trackpad or the mouse wheel: how far the content under the pointer should move, positive to the
  /// right and down, with the user's scroll direction setting applied. `beginsGesture`: the fingers just touched down.
  case scrolled(x: CGFloat, y: CGFloat, isPrecise: Bool, beginsGesture: Bool)
  case pressed(CGPoint)
  case dragged(CGPoint)
  case released(CGPoint)
}

/// The surface of a control that turns by scrolling or dragging, such as the timer's drum. Lay it over the control's
/// drawing. A precise scroll comes from a trackpad or a Magic Mouse, in points; any other from a mouse wheel, about one
/// line per notch. A press counts as `OutsideActivity` until it is released, so a drag that leaves the window does not
/// close it. AppKit-backed: SwiftUI on macOS 14 has no scroll events outside a scroll view.
public struct ScrollDragArea: NSViewRepresentable {
  private let help: String?
  private let onEvent: @MainActor (ScrollDragEvent) -> Void

  /// `help` shows as a tooltip: SwiftUI's `help` on the views under the area never shows through it.
  public init(help: String? = nil, onEvent: @escaping @MainActor (ScrollDragEvent) -> Void) {
    self.help = help
    self.onEvent = onEvent
  }

  public func makeNSView(context: Context) -> ScrollDragView {
    let view = ScrollDragView()
    updateNSView(view, context: context)
    return view
  }

  public func updateNSView(_ view: ScrollDragView, context: Context) {
    view.onEvent = onEvent
    // Set again, even to the same text, the tooltip would start over at every change of the control.
    if view.toolTip != help { view.toolTip = help }
  }
}

public final class ScrollDragView: NSView {
  var onEvent: @MainActor (ScrollDragEvent) -> Void = { _ in }

  private var isPressed = false {
    didSet {
      guard isPressed != oldValue else { return }
      if isPressed {
        OutsideActivity.shared.begin()
        watchForLostRelease()
      } else {
        releaseWatch?.cancel()
        releaseWatch = nil
        OutsideActivity.shared.end()
      }
    }
  }
  private var releaseWatch: Task<Void, Never>?

  override public var isFlipped: Bool { true }

  /// The window may not be key: a window opened by hovering the notch leaves the keyboard to the app in front.
  override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override public func scrollWheel(with event: NSEvent) {
    onEvent(.scrolled(
      x: event.scrollingDeltaX,
      y: event.scrollingDeltaY,
      isPrecise: event.hasPreciseScrollingDeltas,
      beginsGesture: event.phase.contains(.began) || event.phase.contains(.mayBegin)
    ))
  }

  override public func mouseDown(with event: NSEvent) {
    isPressed = true
    onEvent(.pressed(point(of: event)))
  }

  override public func mouseDragged(with event: NSEvent) {
    onEvent(.dragged(point(of: event)))
  }

  override public func mouseUp(with event: NSEvent) {
    onEvent(.released(point(of: event)))
    isPressed = false
  }

  /// Taken off screen in the middle of a press, it gets no release: the press ends here.
  override public func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil { isPressed = false }
    super.viewWillMove(toWindow: newWindow)
  }

  /// A release can also be lost when the window is hidden in the middle of a press, by the shortcut for one. Held on
  /// to, the press would keep the window open for good: it ends once no button is down any more.
  private func watchForLostRelease() {
    releaseWatch = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(500))
        guard let self, !Task.isCancelled else { return }
        if NSEvent.pressedMouseButtons & 1 == 0 {
          self.isPressed = false
          return
        }
      }
    }
  }

  private func point(of event: NSEvent) -> CGPoint {
    convert(event.locationInWindow, from: nil)
  }
}
