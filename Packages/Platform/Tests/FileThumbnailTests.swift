import AppKit
import SwiftUI
import Testing

@testable import VortexPlatform

/// FileThumbnail shows the picture of the file it shows now. The view sits in a window off every display, and the test
/// says when a read ends.
@MainActor
struct FileThumbnailTests {
  /// A read held until the test ends it, as a slow Quick Look read would be.
  @MainActor
  final class HeldRead {
    private var held: CheckedContinuation<Void, Never>?
    private(set) var hasStarted = false
    private(set) var hasEnded = false

    func start() async {
      hasStarted = true
      await withCheckedContinuation { held = $0 }
      hasEnded = true
    }

    func end() {
      held?.resume()
      held = nil
    }
  }

  /// A picture of one colour.
  static func picture(_ color: NSColor) -> NSImage {
    NSImage(size: CGSize(width: 8, height: 8), flipped: false) { rect in
      color.setFill()
      rect.fill()
      return true
    }
  }

  /// The colour in the middle of the view, as drawn now.
  func shownColor(_ host: NSView) throws -> NSColor {
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    return try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
  }

  /// Gives the main actor to the view and its reads until `condition` holds, or for 10 s at most.
  func wait(until condition: () throws -> Bool) async throws {
    let start = ContinuousClock.now
    while try !condition(), ContinuousClock.now - start < .seconds(10) {
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  // Colour management shifts the colours, so the test asks which one shows, not its exact value.
  func isBlue(_ color: NSColor) -> Bool {
    color.blueComponent > color.greenComponent + 0.4 && color.blueComponent > color.redComponent + 0.4
  }

  /// A read that ends after the view moved on to another file is dropped: the other file's picture stays.
  @Test
  func aPictureReadForAFileNoLongerShownIsDropped() async throws {
    let first = URL(filePath: "/thumbnails/first.png")
    let second = URL(filePath: "/thumbnails/second.png")
    let firstRead = HeldRead()
    let read: FileThumbnail<Color>.Read = { url, _, _ in
      guard url == first else { return Self.picture(.blue) }
      await firstRead.start()
      return Self.picture(.red)
    }
    func thumbnail(_ url: URL) -> some View {
      FileThumbnail(url: url, size: CGSize(width: 40, height: 40), read: read) { Color.gray }
        .frame(width: 40, height: 40)
    }
    let host = NSHostingView(rootView: thumbnail(first))
    let window = NSWindow(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 40, height: 40),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    window.orderFrontRegardless()
    defer { window.orderOut(nil) }
    _ = try shownColor(host)
    try await wait { firstRead.hasStarted }
    #expect(firstRead.hasStarted)

    // The view moves on to the second file while the first one is read: the second's picture shows.
    host.rootView = thumbnail(second)
    try await wait { isBlue(try shownColor(host)) }
    #expect(isBlue(try shownColor(host)))

    // The first read ends now, and its task finishes right after, as both are on the main actor.
    firstRead.end()
    try await wait { firstRead.hasEnded }
    try await Task.sleep(for: .milliseconds(100))
    let shown = try shownColor(host)
    #expect(isBlue(shown), "the view shows \(shown)")
  }
}
