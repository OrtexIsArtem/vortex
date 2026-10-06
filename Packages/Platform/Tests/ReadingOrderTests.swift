import CoreGraphics
import Testing

@testable import VortexPlatform

struct ReadingOrderTests {
  /// A line of text 0.02 high, its middle at `y`, from `x`, in Vision's coordinates (0…1, from the bottom left).
  func line(_ text: String, x: CGFloat, y: CGFloat) -> (String, CGRect) {
    (text, CGRect(x: x, y: y - 0.01, width: 0.2, height: 0.02))
  }

  @Test
  func linesGoTopToBottomAndPiecesOfARowLeftToRight() {
    let lines = [
      line("14:18", x: 0.7, y: 0.801),
      line("second line", x: 0.1, y: 0.75),
      line("Oleh", x: 0.1, y: 0.8),
      line("first message", x: 0.1, y: 0.775),
    ]
    #expect(readingOrder(lines, box: \.1).map(\.0) == ["Oleh", "14:18", "first message", "second line"])
  }

  @Test
  func slightlySlantedLinesStillReadInOrder() {
    // Each next piece a little lower than the last, all within a row: one row, left to right.
    let lines = [
      line("c", x: 0.5, y: 0.492),
      line("a", x: 0.1, y: 0.5),
      line("b", x: 0.3, y: 0.496),
    ]
    #expect(readingOrder(lines, box: \.1).map(\.0) == ["a", "b", "c"])
  }
}
