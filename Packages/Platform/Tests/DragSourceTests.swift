import AppKit
import Testing

@testable import VortexPlatform

/// Presses, moves and releases sent straight to the view, as AppKit sends them.
@MainActor
struct DragSourceTests {
  let view = DragSourceView(frame: CGRect(x: 0, y: 0, width: 300, height: 34))

  func event(_ type: NSEvent.EventType, x: CGFloat) -> NSEvent {
    NSEvent.mouseEvent(
      with: type, location: NSPoint(x: x, y: 17), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
      eventNumber: 0, clickCount: 1, pressure: 1
    )!
  }

  /// Presses at x 50 and moves a point at a time to `x`, where it releases.
  func press(releasingAt x: CGFloat) {
    view.mouseDown(with: event(.leftMouseDown, x: 50))
    var position: CGFloat = 50
    while position < x {
      position = min(position + 1, x)
      view.mouseDragged(with: event(.leftMouseDragged, x: position))
    }
    view.mouseUp(with: event(.leftMouseUp, x: x))
  }

  @Test
  func aPressWithNothingToDragStaysAClickWhenThePointerSlips() {
    var clicks = 0
    var asked = 0
    view.items = {
      asked += 1
      return []
    }
    view.onClick = { _ in clicks += 1 }
    press(releasingAt: 50)
    #expect(clicks == 1)
    #expect(asked == 0)
    // 8 pt: past the 4 pt that start a drag, still on the item.
    press(releasingAt: 58)
    #expect(clicks == 2)
    #expect(asked == 1)
  }

  @Test
  func aPressWithNothingToDragReleasedAwayFromTheItemIsNoClick() {
    var clicks = 0
    view.items = { [] }
    view.onClick = { _ in clicks += 1 }
    press(releasingAt: 400)
    #expect(clicks == 0)
  }
}
