import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import VortexPlatform

/// A large picture is read in tiles Vision keeps at full resolution, and the tiles' reads are put back together: a
/// stretch two tiles both read comes once, and a line a tile's edge cuts is stitched where the two reads agree.
struct TextTilesTests {
  // MARK: - Where the picture is cut

  @Test
  func aSmallPictureIsOneTile() {
    #expect(tiles(width: 1_400, height: 900) == [CGRect(x: 0, y: 0, width: 1_400, height: 900)])
    #expect(tiles(width: 1_600, height: 1_600) == [CGRect(x: 0, y: 0, width: 1_600, height: 1_600)])
  }

  /// A whole screen of this Mac, 3,456 × 2,234 px: three columns by two rows of 1,600 px tiles, spread evenly, each
  /// overlapping its neighbours by more than the least overlap.
  @Test
  func aLargePictureIsCutIntoEvenOverlappingTiles() {
    let wide = tiles(width: 3_456, height: 800)
    #expect(wide.map(\.minX) == [0, 928, 1_856])
    #expect(wide.allSatisfy { $0.width == 1_600 && $0.height == 800 && $0.minY == 0 })
    let screen = tiles(width: 3_456, height: 2_234)
    #expect(screen.count == 6)
    #expect(Set(screen.map(\.minY)) == [0, 634])
    #expect(screen.allSatisfy { $0.width == 1_600 && $0.height == 1_600 })
    #expect(screen.reduce(CGRect.null) { $0.union($1) } == CGRect(x: 0, y: 0, width: 3_456, height: 2_234))
    for (left, right) in zip(wide, wide.dropFirst()) {
      #expect(left.maxX - right.minX >= CGFloat(tileOverlap))
    }
  }

  /// A piece cut by an edge a tile shares with the tile above or below is left out: that tile holds it whole. The
  /// picture's own edges cut nothing.
  @Test
  func aPieceCutAtATilesInnerTopOrBottomIsLeftOut() {
    let upper = CGRect(x: 0, y: 0, width: 1_600, height: 1_600)
    let lower = CGRect(x: 0, y: 634, width: 1_600, height: 1_600)
    #expect(isWhole(top: 100, bottom: 130, in: upper, pictureHeight: 2_234))
    #expect(!isWhole(top: 1_580, bottom: 1_600, in: upper, pictureHeight: 2_234))
    #expect(!isWhole(top: 634, bottom: 660, in: lower, pictureHeight: 2_234))
    #expect(isWhole(top: 2_200, bottom: 2_234, in: lower, pictureHeight: 2_234))
    #expect(isWhole(top: 0, bottom: 30, in: upper, pictureHeight: 2_234))
  }

  // MARK: - Putting the reads together

  /// Vision's coordinates, from the bottom left: a piece on the row 0.50–0.52, from `x` to `maxX`.
  func piece(_ text: String, _ x: CGFloat, _ maxX: CGFloat, tile: Int, y: CGFloat = 0.5) -> ReadPiece {
    ReadPiece(text: text, box: CGRect(x: x, y: y, width: maxX - x, height: 0.02), tile: tile)
  }

  /// A word in the overlap that both tiles read comes once; so does a line two rows of tiles both read.
  @Test
  func aStretchTwoTilesBothReadComesOnce() {
    #expect(lines(of: [piece("Line 01 — The quick", 0.0, 0.4, tile: 0), piece("quick", 0.33, 0.4, tile: 1)]) == ["Line 01 — The quick"])
    #expect(lines(of: [piece("14:21", 0.45, 0.5, tile: 1), piece("14:21", 0.45, 0.5, tile: 0)]) == ["14:21"])
    #expect(lines(of: [piece("Next line", 0.1, 0.3, tile: 0), piece("Next line", 0.1, 0.3, tile: 3)]) == ["Next line"])
  }

  /// The same stretch read whole by two tiles comes as the read that parts more words, as Vision's slip in small text is
  /// to run two together; a read that parts no more keeps the first.
  @Test
  func ofTwoReadsOfOneStretchTheOneThatPartsMoreWordsStays() {
    let glued = piece("Line 35- The quick brownfox jumps overthe lazy dog", 0.023, 0.23, tile: 3)
    let parted = piece("Line 35-The quick brown fox jumps over the lazy dog", 0.0234, 0.23, tile: 0)
    #expect(lines(of: [glued, parted]) == ["Line 35-The quick brown fox jumps over the lazy dog"])
    #expect(lines(of: [parted, glued]) == ["Line 35-The quick brown fox jumps over the lazy dog"])
    let other = piece("Line 35 - The quick brown fox", 0.023, 0.23, tile: 3)
    #expect(lines(of: [other, piece("Line 35 — The quick brown fox", 0.023, 0.23, tile: 0)]) == ["Line 35 - The quick brown fox"])
  }

  /// A line a tile's edge cuts: each tile reads its part, cut letters and all, and the two are stitched where they
  /// agree, the cut letters left out.
  @Test
  func aLineCutAtATilesEdgeIsStitchedWhereTheReadsAgree() {
    let left = piece("The quick brown fox jum#", 0.0, 0.5, tile: 0)
    let right = piece("%x jumps over the lazy dog", 0.4, 0.9, tile: 1)
    #expect(lines(of: [right, left]) == ["The quick brown fox jumps over the lazy dog"])
    // Pieces of one tile never merge, even where they touch; a piece next to the stitched line joins with a space.
    let time = piece("14:21", 0.92, 0.98, tile: 1)
    #expect(lines(of: [left, right, time]) == ["The quick brown fox jumps over the lazy dog 14:21"])
  }

  /// Where the two reads don't agree on three letters in a row, each keeps its part up to the overlap's middle.
  @Test
  func readsThatDontAgreeMeetInTheOverlapsMiddle() {
    let left = piece("aaaaaaaaaa", 0.0, 0.5, tile: 0)
    let right = piece("bbbbbbbbbb", 0.4, 0.9, tile: 1)
    #expect(lines(of: [left, right]) == ["aaaaaaaaabbbbbbbbb"])
  }

  // MARK: - Reading with Vision

  /// The tester's screen of 85 numbered lines of 11 pt text, cut 3,456 × 800 px, the whole screen's width: Vision alone
  /// reads nothing in it; in tiles every line of it is read, once.
  @Test(.liveVision)
  func aWidePictureOfSmallTextIsReadWhole() async throws {
    let lines = try await TextRecognitionClient.liveValue.recognize(Fixture.image("dense-wide")).split(separator: "\n")
    let numbers = lines.compactMap { $0.firstMatch(of: /Line (\d\d)/).map { Int($0.1)! } }
    #expect(lines.count >= 29, "\(lines)")
    #expect(Set(numbers).count == numbers.count, "a line twice: \(numbers)")
    #expect(numbers.count >= 29 && numbers.first == 1, "\(numbers)")
    #expect(lines.filter { $0.contains("brown fox jumps over the lazy dog") }.count >= 27, "\(lines)")
  }

  /// The tester's chat, cut the whole screen's width: Vision alone loses two of the 12 pt times and a question mark; in
  /// tiles each line comes whole, with its time.
  @Test(.liveVision)
  func aWideChatKeepsItsTimes() async throws {
    let text = try await TextRecognitionClient.liveValue.recognize(Fixture.image("chat-wide"))
    #expect(text == "Build 43 failed on main again 14:21\nCan you look at the error? 14:22\nSure, sending the log now 14:25")
  }

  /// Lines of 11 pt text set close, as in a log, across a whole screen's width, 3,456 × 800 px, which Vision alone reads
  /// little of and three tiles cut twice each: every line, whole, once.
  @Test(.liveVision)
  func linesAcrossTheTilesAreReadWhole() async throws {
    let sentences = (1...28).map { number in
      "Step \(number) of the release: the tests in the payments module could not reach the staging server"
        + " and the retry gave up after three attempts, so the build waits for a fix"
    }
    let picture = Self.picture(sentences, width: 3_456, height: 800, size: 22, pitch: 26)
    let text = try await TextRecognitionClient.liveValue.recognize(picture)
    #expect(text.split(separator: "\n").map(String.init) == sentences)
  }

  /// A picture `width` × `height` px with lines of black text `size` px high on white, from the top left, a line every
  /// `pitch` px.
  static func picture(_ lines: [String], width: Int, height: Int, size: CGFloat, pitch: CGFloat) -> ScreenImage {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
    ]
    for (row, line) in lines.enumerated() {
      context.textPosition = CGPoint(x: 24, y: CGFloat(height) - size * 1.5 - pitch * CGFloat(row))
      CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes)), context)
    }
    return ScreenImage(cgImage: context.makeImage()!, scale: 2)
  }
}
