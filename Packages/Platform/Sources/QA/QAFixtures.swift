#if DEBUG
  import AppKit
  import VortexCore

  /// What the simulated services show: a few well-known apps, and a display picture made here or put in by a tester.
  enum QAFixtures {
    static let finder = "com.apple.finder"

    /// Apps every Mac has, so their icons draw.
    static let runningApps: [AppInfo] = [
      AppInfo(bundleID: finder, name: "Finder"),
      AppInfo(bundleID: "com.apple.Safari", name: "Safari"),
      AppInfo(bundleID: "com.apple.systempreferences", name: "System Settings"),
      AppInfo(bundleID: "com.apple.Terminal", name: "Terminal"),
      AppInfo(bundleID: "com.apple.TextEdit", name: "TextEdit"),
    ]

    static func name(of bundleID: String) -> String {
      runningApps.first { $0.bundleID == bundleID }?.name ?? bundleID
    }

    /// The main display as a capture sees it: fixtures/screen.png in the run's folder when there is one, otherwise a
    /// plain dark picture with two light windows on it, the main display's size. Never a real screenshot.
    @MainActor
    static func screenshot() -> Screenshot {
      let screen = NSScreen.screens.first
      let scale = screen?.backingScaleFactor ?? 2
      let size = screen?.frame.size ?? CGSize(width: 1512, height: 982)
      let file = QAPaths.fixturesFolder.appending(path: "screen.png")
      let image = ScreenImage(contentsOf: file, scale: scale) ?? drawn(size: size, scale: scale)
      return Screenshot(
        image: image,
        notch: screen?.notchInPoints,
        bottomInset: screen?.dockHeight ?? 0,
        displayID: screen?.displayNumber ?? 0
      )
    }

    private static func drawn(size: CGSize, scale: CGFloat) -> ScreenImage {
      let width = Int(size.width * scale)
      let height = Int(size.height * scale)
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
      )!
      context.setFillColor(CGColor(gray: 0.15, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      context.setFillColor(CGColor(gray: 0.85, alpha: 1))
      context.fill(CGRect(x: width / 10, y: height / 5, width: width / 2, height: height / 2))
      context.setFillColor(CGColor(gray: 0.6, alpha: 1))
      context.fill(CGRect(x: width / 2, y: height / 3, width: width / 3, height: height / 3))
      return ScreenImage(cgImage: context.makeImage()!, scale: scale)
    }
  }
#endif
