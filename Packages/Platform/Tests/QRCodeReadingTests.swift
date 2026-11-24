import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation
import Testing

@testable import VortexPlatform

/// QR codes read by Apple Vision on this Mac, from a part of the screen.
struct QRCodeReadingTests {
  /// A white picture `width` × `height` px at 2 px per point, with a QR code of each payload at its x, `side` px wide,
  /// and a line of black text under them.
  static func image(
    width: Int = 900,
    height: Int = 420,
    codes: [(payload: String, x: Int)] = [],
    side: Int = 240,
    text: String? = nil
  ) -> ScreenImage {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .none
    for code in codes {
      context.draw(qrCode(code.payload, side: side), in: CGRect(x: code.x, y: height - side - 40, width: side, height: side))
    }
    if let text {
      let font = CTFontCreateUIFontForLanguage(.system, 36, nil)!
      let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
      ]
      context.textPosition = CGPoint(x: 40, y: 50)
      CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
    }
    return ScreenImage(cgImage: context.makeImage()!, scale: 2)
  }

  /// A QR code of `payload`, `side` px wide, its modules sharp.
  static func qrCode(_ payload: String, side: Int) -> CGImage {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(payload.utf8)
    filter.correctionLevel = "M"
    let code = filter.outputImage!
    let scale = CGFloat(side) / code.extent.width
    let scaled = code.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    return CIContext().createCGImage(scaled, from: scaled.extent)!
  }

  @Test(.liveVision)
  func readsALinkInAQRCode() async throws {
    let payload = try await TextRecognitionClient.liveValue.readQRCode(Self.image(codes: [("https://example.com/a?b=c", 60)]))
    #expect(payload == "https://example.com/a?b=c")
  }

  @Test(.liveVision)
  func readsAnyTextInAQRCode() async throws {
    let payload = try await TextRecognitionClient.liveValue.readQRCode(Self.image(codes: [("WIFI:S:Office;T:WPA;P:demo;;", 60)]))
    #expect(payload == "WIFI:S:Office;T:WPA;P:demo;;")
  }

  /// Of two codes, the larger one is the one the frame is about.
  @Test(.liveVision)
  func ofTwoCodesTheLargerOneIsRead() async throws {
    let context = CGContext(
      data: nil, width: 900, height: 420, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 900, height: 420))
    context.interpolationQuality = .none
    context.draw(Self.qrCode("small", side: 150), in: CGRect(x: 40, y: 200, width: 150, height: 150))
    context.draw(Self.qrCode("large", side: 300), in: CGRect(x: 400, y: 60, width: 300, height: 300))
    let payload = try await TextRecognitionClient.liveValue.readQRCode(ScreenImage(cgImage: context.makeImage()!, scale: 2))
    #expect(payload == "large")
  }

  @Test(.liveVision)
  func textWithoutACodeIsNoCode() async throws {
    let payload = try await TextRecognitionClient.liveValue.readQRCode(Self.image(text: "No code here, only text"))
    #expect(payload == nil)
  }
}
