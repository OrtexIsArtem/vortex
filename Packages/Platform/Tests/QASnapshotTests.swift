#if DEBUG
  import AppKit
  import Testing

  @testable import VortexPlatform

  /// QA's snapshots draw what Core Animation tints with a `multiplyColor` filter in that tint, as the screen does; plain
  /// `cacheDisplay` (layer rendering) leaves it white, which made three sidebar icons look white (B-B3).
  @MainActor
  struct QASnapshotTests {
    static let grey = CGColor(srgbRed: 0x6B / 255, green: 0x6B / 255, blue: 0x70 / 255, alpha: 1)
    static let background = CGColor(srgbRed: 0xFB / 255, green: 0xFB / 255, blue: 0xFC / 255, alpha: 1)

    /// Core Animation's own filter, as SwiftUI sets it on a tinted symbol.
    static func multiplyColor(_ color: CGColor) throws -> NSObject {
      let type = try #require(NSClassFromString("CAFilter") as? NSObject.Type)
      let made = type.perform(NSSelectorFromString("filterWithType:"), with: "multiplyColor")?.takeUnretainedValue()
      let filter = try #require(made as? NSObject)
      filter.setValue(color, forKey: "inputColor")
      return filter
    }

    /// A white square, as SwiftUI's template image of a symbol is white under the filter.
    static func whiteImage() throws -> CGImage {
      let context = try #require(CGContext(
        data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ))
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
      return try #require(context.makeImage())
    }

    /// A 40 × 20 pt light window whose layer at (10, 5, 10, 10) is a white image tinted grey by the filter.
    func makeTree(parentOpacity: Float = 1) throws -> (root: CALayer, tinted: CALayer) {
      let root = CALayer()
      root.frame = CGRect(x: 0, y: 0, width: 40, height: 20)
      root.backgroundColor = Self.background
      let parent = CALayer()
      parent.frame = root.bounds
      parent.opacity = parentOpacity
      root.addSublayer(parent)
      let tinted = CALayer()
      tinted.frame = CGRect(x: 10, y: 5, width: 10, height: 10)
      tinted.filters = [try Self.multiplyColor(Self.grey)]
      let drawing = CALayer()
      drawing.frame = tinted.bounds
      drawing.contents = try Self.whiteImage()
      tinted.addSublayer(drawing)
      parent.addSublayer(tinted)
      return (root, tinted)
    }

    /// Draws the tree as the snapshot does, at 2 px a point, and returns the pixel at (x, y) in points.
    func snapshotPixel(_ root: CALayer, at point: CGPoint) throws -> (r: Int, g: Int, b: Int) {
      let width = 80, height = 40
      var pixels = [UInt8](repeating: 0, count: width * height * 4)
      let context = try #require(CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ))
      context.scaleBy(x: 2, y: 2)
      let tinted = QASnapshot.tintedLayers(in: root)
      for item in tinted { item.layer.isHidden = true }
      root.render(in: context)
      for item in tinted { item.layer.isHidden = false }
      QASnapshot.drawTints(tinted, root: root, into: context)
      context.flush()
      // CGContext rows run from the top of the bitmap: y in points counts from the bottom.
      let row = height - 1 - Int(point.y * 2)
      let index = (row * width + Int(point.x * 2)) * 4
      return (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
    }

    @Test
    func aLayerTintedByMultiplyColorIsDrawnInItsTintNotWhite() throws {
      let (root, tinted) = try makeTree()
      #expect(QASnapshot.tintedLayers(in: root).map(\.layer) == [tinted])
      #expect(QASnapshot.multiplyColor(of: tinted) == Self.grey)
      let inside = try snapshotPixel(root, at: CGPoint(x: 15, y: 10))
      #expect(abs(inside.r - 0x6B) <= 2 && abs(inside.g - 0x6B) <= 2 && abs(inside.b - 0x70) <= 2)
      let outside = try snapshotPixel(root, at: CGPoint(x: 30, y: 10))
      #expect(outside.r == 0xFB && outside.b == 0xFC)
    }

    /// Under a layer that doesn't show (keyboard cleaning's screen hides the tabs that way), nothing is drawn.
    @Test
    func aTintedLayerUnderAnInvisibleOneIsNotDrawn() throws {
      let (root, _) = try makeTree(parentOpacity: 0)
      let inside = try snapshotPixel(root, at: CGPoint(x: 15, y: 10))
      #expect(inside.r == 0xFB && inside.b == 0xFC)
    }

    /// Without the filter, plain layer rendering draws the template white: what the snapshots showed before.
    @Test
    func plainLayerRenderingLeavesTheTemplateWhite() throws {
      let (root, _) = try makeTree()
      let width = 80, height = 40
      var pixels = [UInt8](repeating: 0, count: width * height * 4)
      let context = try #require(CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ))
      context.scaleBy(x: 2, y: 2)
      root.render(in: context)
      let index = ((height - 1 - 20) * width + 30) * 4
      #expect(pixels[index] == 255 && pixels[index + 2] == 255)
    }
  }
#endif
