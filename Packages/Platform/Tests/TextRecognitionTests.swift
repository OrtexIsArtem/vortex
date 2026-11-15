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
  /// A PNG `width` × `height` px: lines of black text `size` px high on white, one row each from the top, each from its
  /// own `x`.
  static func png(width: Int, height: Int, size: CGFloat, lines: [(text: String, x: CGFloat)]) -> Data {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
    for (row, line) in lines.enumerated() {
      let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
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

  @Test
  func dataThatIsNotAnImageThrows() async {
    await #expect(throws: (any Error).self) {
      try await TextRecognitionClient.liveValue.recognizeForSearch(Data("mcp server".utf8))
    }
    await #expect(throws: (any Error).self) { try await TextRecognitionClient.liveValue.recognizeForSearch(Data()) }
  }
}
