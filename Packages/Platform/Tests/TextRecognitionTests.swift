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
  /// transparent), one row each from the top, each from its own `x`.
  static func png(
    width: Int,
    height: Int,
    size: CGFloat,
    lines: [(text: String, x: CGFloat)],
    color: CGColor = CGColor(gray: 0, alpha: 1),
    background: CGColor? = CGColor(gray: 1, alpha: 1)
  ) -> Data {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    if let background {
      context.setFillColor(background)
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
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

  @Test
  func readsEnglishAndUkrainian() async throws {
    let png = Self.png(width: 1_200, height: 360, size: 48, lines: [("mcp server", 48), ("Налаштування сервера", 48)])
    let text = try await TextRecognitionClient.liveValue.recognizeForSearch(png).lowercased()
    #expect(text.contains("mcp server"))
    #expect(text.contains("налаштування сервера"))
  }

  @Test
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
  @Test(arguments: [0, 1] as [CGFloat])
  func textOnATransparentBackgroundIsRead(gray: CGFloat) async throws {
    let png = Self.png(
      width: 1_200, height: 300, size: 48, lines: [("mcp server release", 48)], color: CGColor(gray: gray, alpha: 1),
      background: nil
    )
    let text = try await TextRecognitionClient.liveValue.recognizeForSearch(png).lowercased()
    #expect(text.contains("mcp server release"))
  }

  @Test
  func anImageThatShowsThroughIsReadOverWhiteOrOverBlackWhenWhatItShowsIsLightAndAnOpaqueOneAsItIs() throws {
    func decoded(color: CGColor, background: CGColor?) throws -> CGImage {
      try searchedImage(
        Self.png(width: 600, height: 200, size: 48, lines: [("mcp", 48)], color: color, background: background)
      )
    }
    let black = CGColor(gray: 0, alpha: 1)
    let white = CGColor(gray: 1, alpha: 1)
    #expect(Self.corner(try decoded(color: black, background: nil)) == [255, 255, 255, 255])
    #expect(Self.corner(try decoded(color: CGColor(gray: 0, alpha: 0.5), background: nil)) == [255, 255, 255, 255])
    #expect(Self.corner(try decoded(color: white, background: nil)) == [0, 0, 0, 255])
    // Drawn on white, the PNG still has an alpha channel, but nothing shows through.
    let opaqueImage = try decoded(color: black, background: white)
    #expect(opaque(opaqueImage) === opaqueImage)
    #expect(Self.corner(opaqueImage) == [255, 255, 255, 255])
  }

  @Test
  func dataThatIsNotAnImageThrows() async {
    await #expect(throws: (any Error).self) {
      try await TextRecognitionClient.liveValue.recognizeForSearch(Data("mcp server".utf8))
    }
    await #expect(throws: (any Error).self) { try await TextRecognitionClient.liveValue.recognizeForSearch(Data()) }
  }
}
