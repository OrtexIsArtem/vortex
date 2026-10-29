#if DEBUG
  import AppKit
  import Testing

  @testable import VortexPlatform

  /// QA's snapshots show what Core Animation tints with a `multiplyColor` filter in that tint, exactly where and as much
  /// as the screen shows it: clipped, scrolled out, covered or faded like any other layer (B-B3, N3).
  ///
  /// Each case is drawn twice: as the screen shows it, a drawing already in its tint rendered plainly; and as a QA
  /// snapshot draws it, a white template under the filter, tinted in place. The two must match pixel for pixel.
  @MainActor
  struct QASnapshotTests {
    static let grey = CGColor(srgbRed: 0x6B / 255, green: 0x6B / 255, blue: 0x70 / 255, alpha: 1)
    static let red = CGColor(srgbRed: 1, green: 0.5, blue: 0.25, alpha: 1)
    static let background = CGColor(srgbRed: 0xFB / 255, green: 0xFB / 255, blue: 0xFC / 255, alpha: 1)
    static let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    /// Core Animation's own filter, as SwiftUI sets it on a tinted symbol.
    static func multiplyColor(_ color: CGColor) throws -> NSObject {
      let type = try #require(NSClassFromString("CAFilter") as? NSObject.Type)
      let made = type.perform(NSSelectorFromString("filterWithType:"), with: "multiplyColor")?.takeUnretainedValue()
      let filter = try #require(made as? NSObject)
      filter.setValue(color, forKey: "inputColor")
      return filter
    }

    /// 20 × 20 px in `color`, the upper half only, so a drawing shown upside down shows.
    static func upperHalf(_ color: CGColor) throws -> CGImage {
      let context = try #require(CGContext(
        data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ))
      context.setFillColor(color)
      context.fill(CGRect(x: 0, y: 10, width: 20, height: 10))
      return try #require(context.makeImage())
    }

    /// The components of two colours multiplied, as one filter inside another multiplies them.
    static func product(_ a: CGColor, _ b: CGColor) -> CGColor {
      let x = a.components!, y = b.components!
      return CGColor(srgbRed: x[0] * y[0], green: x[1] * y[1], blue: x[2] * y[2], alpha: x[3] * y[3])
    }

    /// A symbol as SwiftUI draws it: a white template under `tints` (outermost first), one filtered layer each. For the
    /// screen's view, the same layers without filters and the drawing already in its colour.
    static func symbol(_ frame: CGRect, tints: [CGColor] = [grey], asScreen: Bool) throws -> CALayer {
      let outer = CALayer()
      outer.frame = frame
      var current = outer
      for (index, tint) in tints.enumerated() {
        if !asScreen { current.filters = [try multiplyColor(tint)] }
        guard index < tints.count - 1 else { break }
        let inner = CALayer()
        inner.frame = current.bounds
        current.addSublayer(inner)
        current = inner
      }
      let drawing = CALayer()
      drawing.frame = current.bounds
      drawing.contents = try upperHalf(asScreen ? tints.reduce(white, product) : white)
      current.addSublayer(drawing)
      return outer
    }

    /// A 40 × 20 pt light window built by `scene`, which gets the symbol to place.
    static func window(asScreen: Bool, _ scene: (CALayer, Bool) throws -> Void) rethrows -> CALayer {
      let root = CALayer()
      root.frame = CGRect(x: 0, y: 0, width: 40, height: 20)
      root.backgroundColor = background
      try scene(root, asScreen)
      return root
    }

    /// The window's pixels at 2 px a point: plainly for the screen's view, through the snapshot's tinting otherwise.
    static func pixels(_ root: CALayer, snapshot: Bool) throws -> [UInt8] {
      let width = 80, height = 40
      var pixels = [UInt8](repeating: 0, count: width * height * 4)
      try pixels.withUnsafeMutableBytes { buffer in
        let context = try #require(CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.scaleBy(x: 2, y: 2)
        if snapshot {
          QASnapshot.withTintsInPlace(in: root, scale: 2) { root.render(in: context) }
        } else {
          root.render(in: context)
        }
      }
      return pixels
    }

    /// The snapshot matches the screen everywhere; returns how many pixels differ from the plain background.
    @discardableResult
    func expectSnapshotMatchesScreen(_ scene: (CALayer, Bool) throws -> Void) throws -> Int {
      let screen = try Self.pixels(Self.window(asScreen: true, scene), snapshot: false)
      let snapshot = try Self.pixels(Self.window(asScreen: false, scene), snapshot: true)
      let differing = zip(screen, snapshot).filter { abs(Int($0) - Int($1)) > 3 }.count
      #expect(differing == 0)
      let background: [UInt8] = [0xFB, 0xFB, 0xFC, 0xFF]
      return stride(from: 0, to: screen.count, by: 4).filter { Array(screen[$0..<$0 + 4]) != background }.count
    }

    @Test
    func aTintedSymbolIsDrawnInItsTintWhereTheScreenShowsIt() throws {
      let drawn = try expectSnapshotMatchesScreen { root, asScreen in
        root.addSublayer(try Self.symbol(CGRect(x: 10, y: 5, width: 10, height: 10), asScreen: asScreen))
      }
      // The upper half of a 10 pt square at 2 px a point.
      #expect(drawn == 200)
    }

    /// Clipped by an ancestor, as a scroll view clips its rows: only the part inside shows.
    @Test
    func aClippedSymbolShowsOnlyWhereItsAncestorShowsIt() throws {
      let drawn = try expectSnapshotMatchesScreen { root, asScreen in
        let clip = CALayer()
        clip.frame = CGRect(x: 0, y: 0, width: 15, height: 20)
        clip.masksToBounds = true
        root.addSublayer(clip)
        clip.addSublayer(try Self.symbol(CGRect(x: 10, y: 5, width: 10, height: 10), asScreen: asScreen))
      }
      #expect(drawn == 100)
    }

    /// Scrolled out of a list: nothing shows.
    @Test
    func aSymbolScrolledOutOfViewDoesNotShow() throws {
      let drawn = try expectSnapshotMatchesScreen { root, asScreen in
        let scroll = CALayer()
        scroll.frame = root.bounds
        scroll.masksToBounds = true
        scroll.bounds.origin = CGPoint(x: 0, y: 30)
        root.addSublayer(scroll)
        scroll.addSublayer(try Self.symbol(CGRect(x: 10, y: 5, width: 10, height: 10), asScreen: asScreen))
      }
      #expect(drawn == 0)
    }

    /// Covered by a layer above it: the cover shows, not the symbol.
    @Test
    func aCoveredSymbolStaysCovered() throws {
      try expectSnapshotMatchesScreen { root, asScreen in
        root.addSublayer(try Self.symbol(CGRect(x: 10, y: 5, width: 10, height: 10), asScreen: asScreen))
        let cover = CALayer()
        cover.frame = CGRect(x: 8, y: 3, width: 14, height: 14)
        cover.backgroundColor = CGColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        root.addSublayer(cover)
      }
    }

    /// Faded or hidden above it, as keyboard cleaning's screen hides the tabs: as much as the screen shows.
    @Test
    func aSymbolUnderAFadedOrInvisibleLayerShowsAsMuchAsOnScreen() throws {
      for opacity: Float in [0, 0.5] {
        let drawn = try expectSnapshotMatchesScreen { root, asScreen in
          let parent = CALayer()
          parent.frame = root.bounds
          parent.opacity = opacity
          root.addSublayer(parent)
          parent.addSublayer(try Self.symbol(CGRect(x: 10, y: 5, width: 10, height: 10), asScreen: asScreen))
        }
        #expect((drawn == 0) == (opacity == 0))
      }
    }

    /// Under a geometry-flipped ancestor, as AppKit's flipped views are, the drawing keeps its orientation and place.
    @Test
    func aSymbolUnderAFlippedAncestorKeepsItsOrientation() throws {
      try expectSnapshotMatchesScreen { root, asScreen in
        let flipped = CALayer()
        flipped.frame = root.bounds
        flipped.isGeometryFlipped = true
        root.addSublayer(flipped)
        flipped.addSublayer(try Self.symbol(CGRect(x: 10, y: 2, width: 10, height: 10), asScreen: asScreen))
      }
    }

    /// A tint inside another: both multiply, not the outer one alone.
    @Test
    func aTintInsideAnotherIsMultipliedByBoth() throws {
      try expectSnapshotMatchesScreen { root, asScreen in
        root.addSublayer(try Self.symbol(CGRect(x: 10, y: 5, width: 10, height: 10), tints: [Self.red, Self.grey], asScreen: asScreen))
      }
    }

    /// The tree is as it was afterwards: the originals show, with their filters, and no stand-in is left.
    @Test
    func theTreeIsPutBackAfterTheSnapshot() throws {
      let root = try Self.window(asScreen: false) { root, asScreen in
        root.addSublayer(try Self.symbol(CGRect(x: 10, y: 5, width: 10, height: 10), asScreen: asScreen))
      }
      let symbol = try #require(root.sublayers?.first)
      var during: [CALayer] = []
      QASnapshot.withTintsInPlace(in: root, scale: 2) { during = root.sublayers ?? [] }
      #expect(during.count == 2)
      #expect(symbol.isHidden == false)
      #expect(root.sublayers?.count == 1)
      #expect(QASnapshot.multiplyColor(of: symbol) == Self.grey)
    }

    /// Plain layer rendering, which `cacheDisplay` uses, leaves the template white: why the sidebar's three symbols
    /// looked white in snapshots before.
    @Test
    func plainLayerRenderingLeavesTheTemplateWhite() throws {
      let root = try Self.window(asScreen: false) { root, asScreen in
        root.addSublayer(try Self.symbol(CGRect(x: 10, y: 5, width: 10, height: 10), asScreen: asScreen))
      }
      let pixels = try Self.pixels(root, snapshot: false)
      // (15, 12) pt: in the drawing's upper half.
      let index = ((40 - 1 - 24) * 80 + 30) * 4
      #expect(pixels[index] == 255 && pixels[index + 1] == 255 && pixels[index + 2] == 255)
    }
  }
#endif
