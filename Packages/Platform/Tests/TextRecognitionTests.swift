import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import VortexPlatform

/// Search's reading of an image's data, by Apple Vision on this Mac: without language correction, from the image scaled
/// down to at most 4,096 px.
struct TextRecognitionForSearchTests {
  /// A PNG `width` × `height` px with an alpha channel: lines of `color` text `size` px high on `background` (nil:
  /// transparent), one row each from the top, each from its own `x`, over `fills` (rounded by their `radius`).
  static func png(
    width: Int,
    height: Int,
    size: CGFloat,
    lines: [(text: String, x: CGFloat)],
    color: CGColor = CGColor(gray: 0, alpha: 1),
    background: CGColor? = CGColor(gray: 1, alpha: 1),
    fills: [(rect: CGRect, radius: CGFloat, color: CGColor)] = []
  ) -> Data {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    if let background {
      context.setFillColor(background)
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    for fill in fills {
      context.setFillColor(fill.color)
      context.addPath(CGPath(roundedRect: fill.rect, cornerWidth: fill.radius, cornerHeight: fill.radius, transform: nil))
      context.fillPath()
    }
    let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
    for (row, line) in lines.enumerated() {
      let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
      ]
      context.textPosition = CGPoint(x: line.x, y: CGFloat(height) - size * CGFloat(2 + 2 * row))
      CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: line.text, attributes: attributes)), context)
    }
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
  }

  @Test(.liveVision)
  func readsEnglishAndUkrainian() async throws {
    let png = Self.png(width: 1_200, height: 360, size: 48, lines: [("mcp server", 48), ("Налаштування сервера", 48)])
    let text = try await TextRecognitionClient.liveValue.recognizeForSearch(png).lowercased()
    #expect(text.contains("mcp server"))
    #expect(text.contains("налаштування сервера"))
  }

  @Test(.liveVision)
  func anImageWiderThan4096PxIsScaledDownAndStillRead() async throws {
    // Large text at both ends: scaled to 4,096 px, it is still about 80 px high.
    let png = Self.png(width: 6_000, height: 800, size: 120, lines: [("mcp server", 120), ("release notes", 4_200)])
    let text = try await TextRecognitionClient.liveValue.recognizeForSearch(png).lowercased()
    #expect(text.contains("mcp server"))
    #expect(text.contains("release notes"))
  }

  @Test
  func aLongerSideOver4096PxIsScaledDownAndASmallerImageNeverUp() throws {
    let wide = try searchedImage(Self.png(width: 6_000, height: 800, size: 120, lines: [("mcp server", 120)]))
    #expect(wide.width == 4_096)
    #expect(abs(wide.height - 800 * 4_096 / 6_000) <= 1)
    let tall = try searchedImage(Self.png(width: 300, height: 5_000, size: 40, lines: [("mcp", 40)]))
    #expect(tall.height == 4_096)
    let small = try searchedImage(Self.png(width: 900, height: 240, size: 40, lines: [("mcp server", 40)]))
    #expect((small.width, small.height) == (900, 240))
  }

  /// The top left pixel of an image in 8-bit sRGB: red, green, blue and alpha.
  static func corner(_ image: CGImage) -> [UInt8] {
    let context = CGContext(
      data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // At its own size, with its top left pixel on the context's only one.
    context.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
    let pixel = context.data!.assumingMemoryBound(to: UInt8.self)
    return (0..<4).map { pixel[$0] }
  }

  /// Text with nothing behind it, as on a diagram, a logo or a text layer copied from a design app: dark (Vision takes
  /// a transparent pixel for black) or white.
  @Test(.liveVision, arguments: [0, 1] as [CGFloat])
  func textOnATransparentBackgroundIsRead(gray: CGFloat) async throws {
    let png = Self.png(
      width: 1_200, height: 300, size: 48, lines: [("mcp server release", 48)], color: CGColor(gray: gray, alpha: 1),
      background: nil
    )
    let text = try await TextRecognitionClient.liveValue.recognizeForSearch(png).lowercased()
    #expect(text.contains("mcp server release"))
  }

  /// "vortex" in `gray`, 120 px high, on transparency beside a larger rounded badge of the other shade, as a logo has
  /// its name beside its mark.
  static func wordmark(gray: CGFloat) -> Data {
    png(
      width: 1_200, height: 400, size: 120, lines: [("vortex", 40)], color: CGColor(gray: gray, alpha: 1),
      background: nil, fills: [(CGRect(x: 780, y: 20, width: 360, height: 360), 72, CGColor(gray: 1 - gray, alpha: 1))]
    )
  }

  /// A title in `gray` on transparency, over a card of the other shade that takes three quarters of the image and
  /// holds a line in `gray` of its own.
  static func titledCard(gray: CGFloat) -> Data {
    png(
      width: 1_200, height: 600, size: 48, lines: [("mcp server", 48), ("release notes", 48)],
      color: CGColor(gray: gray, alpha: 1), background: nil,
      fills: [(CGRect(x: 0, y: 0, width: 1_200, height: 460), 0, CGColor(gray: 1 - gray, alpha: 1))]
    )
  }

  @Test
  func anImageThatShowsThroughIsReadOverWhiteThenOverBlackAndAnOpaqueOneOnceAsItIs() throws {
    let black = CGColor(gray: 0, alpha: 1)
    let white = CGColor(gray: 1, alpha: 1)
    for color in [black, CGColor(gray: 0, alpha: 0.5), white] {
      let image = try searchedImage(
        Self.png(width: 600, height: 200, size: 48, lines: [("mcp", 48)], color: color, background: nil)
      )
      let read = backgrounds(for: image).map { Self.corner(drawn(image, over: $0)) }
      #expect(read == [[255, 255, 255, 255], [0, 0, 0, 255]])
    }
    // Drawn on white, the PNG still has an alpha channel, but nothing shows through.
    let opaqueImage = try searchedImage(
      Self.png(width: 600, height: 200, size: 48, lines: [("mcp", 48)], color: black, background: white)
    )
    #expect(backgrounds(for: opaqueImage).map { $0 == nil } == [true])
    #expect(drawn(opaqueImage, over: nil) === opaqueImage)
  }

  /// Text on transparency is read whatever its shade and whatever sits beside it, such as a larger fill of the other
  /// shade, which one background picked for the whole image would hide it on: a logo's name beside its mark, a title
  /// over a card. A line read over both backgrounds, as the card's own is, comes once.
  @Test(.liveVision, arguments: [0, 1] as [CGFloat])
  func textOnTransparencyBesideALargerFillOfTheOtherShadeIsRead(gray: CGFloat) async throws {
    let read = TextRecognitionClient.liveValue.recognizeForSearch
    #expect(try await read(Self.wordmark(gray: gray)).lowercased().contains("vortex"))
    let card = try await read(Self.titledCard(gray: gray)).lowercased().split(separator: "\n")
    #expect(card.contains { $0.contains("mcp server") })
    #expect(card.filter { $0.contains("release notes") }.count == 1)
  }

  /// A PNG Vision takes about a second to read on the owner's Mac: 82 long rows of 24 px text on a 4,000 px square.
  static let longRead = png(
    width: 4_000, height: 4_000, size: 24,
    lines: (0..<82).map { row in
      (String(repeating: "row \(row): mcp server release, налаштування сервера \(row * 7); ", count: 4), 40)
    }
  )

  @Test
  func aReadGivenUpBeforeItStartsReadsNothing() async {
    let png = Self.longRead
    let read = Task { try await TextRecognitionClient.liveValue.recognizeForSearch(png) }
    read.cancel()
    await #expect(throws: CancellationError.self) { try await read.value }
  }

  @Test(.liveVision)
  func aReadGivenUpWhileVisionReadsStopsVisionAndBringsNoText() async throws {
    let png = Self.longRead
    let read = Task { try await TextRecognitionClient.liveValue.recognizeForSearch(png) }
    // Decoded by now, and Vision a third of the way through it, or still busy with another test's read first.
    try await Task.sleep(for: .milliseconds(300))
    read.cancel()
    await #expect(throws: CancellationError.self) { try await read.value }
  }

  @Test
  func dataThatIsNotAnImageThrows() async {
    await #expect(throws: (any Error).self) {
      try await TextRecognitionClient.liveValue.recognizeForSearch(Data("mcp server".utf8))
    }
    await #expect(throws: (any Error).self) { try await TextRecognitionClient.liveValue.recognizeForSearch(Data()) }
  }
}
