import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import VortexPlatform

/// Pictures for the reading tests: crops of the screens QA's tester drew for Screen Text, at 2 px per point.
enum Fixture {
  static func image(_ name: String) throws -> ScreenImage {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Fixtures"))
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return ScreenImage(cgImage: image, scale: 2)
  }
}

/// What reads as one line on the screen comes out as one line: the pieces Vision reads on a row, joined by a space in
/// their order, and the rows top to bottom.
struct TextLinesTests {
  /// A chat's messages with their times at the right end: each line whole, its time and all.
  @Test(.liveVision)
  func aRowsPiecesJoinWithASpaceAndRowsWithALineBreak() async throws {
    let text = try await TextRecognitionClient.liveValue.recognize(Fixture.image("chat"))
    #expect(text == "Build 43 failed on main again 14:21\nCan you look at the error? 14:22\nSure, sending the log now 14:25")
  }

  /// A terminal's lines, each a number and a path that Vision reads in up to four pieces: one line each, whole, with
  /// its number at its start where Vision finds it (it misses some of these short numbers, which is Vision's own).
  @Test(.liveVision)
  func aLineNumberAndThePiecesOfALineStayOnItsLine() async throws {
    let lines = try await TextRecognitionClient.liveValue.recognize(Fixture.image("terminal")).split(separator: "\n")
    #expect(lines.count == 10, "\(lines)")
    for (index, line) in lines.enumerated() {
      let number = String(format: "%02d", index + 1)
      let path = "/Users/dev/Projects/App/Sources/Feature/File\(number).swift:"
      #expect(line.hasPrefix(path) || line.hasPrefix("\(number) \(path)"), "\(line)")
      #expect(line.contains("error: cannot find"), "\(line)")
      #expect(line.hasSuffix("in scope"), "\(line)")
    }
    #expect(lines.filter { $0.hasPrefix("0") }.count >= 2, "\(lines)")
  }

  /// A smaller piece set on the row's baseline, as a time beside a message, overlaps the row: it shares it, whatever
  /// its middle; a piece that doesn't overlap starts the next row.
  @Test
  func aSmallerPieceOnTheBaselineSharesTheRow() {
    // Vision's coordinates, from the bottom left: a message 0.08 high, a time 0.05 high on its baseline, and a line under.
    let pieces = [
      ("14:21", CGRect(x: 0.8, y: 0.70, width: 0.08, height: 0.05)),
      ("Build 43 failed", CGRect(x: 0.05, y: 0.69, width: 0.5, height: 0.08)),
      ("Next line", CGRect(x: 0.05, y: 0.55, width: 0.3, height: 0.08)),
    ]
    #expect(readingLines(pieces, box: \.1, text: \.0) == ["Build 43 failed 14:21", "Next line"])
  }
}
