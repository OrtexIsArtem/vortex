import AppKit
import SwiftUI
import Testing
import VortexCore

@testable import VortexShell

/// A feature's page reads its still off the main thread: the page shows the feature's symbol on its card at once, and
/// the still once it's read. The preview sits in a window off every display.
@MainActor
struct FeaturePreviewTests {
  /// A still of one colour, in a file of its own.
  func still(_ color: NSColor) throws -> URL {
    let bitmap = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 50, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    color.setFill()
    NSRect(x: 0, y: 0, width: 80, height: 50).fill()
    NSGraphicsContext.restoreGraphicsState()
    let url = FileManager.default.temporaryDirectory.appending(path: "still-\(UUID().uuidString).png")
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    return url
  }

  /// The colour the preview shows away from its symbol and its rounded corners, as drawn now.
  func shownColor(_ host: NSView) throws -> NSColor {
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
    return try #require(bitmap.colorAt(x: Int(40 * scale), y: Int(30 * scale))?.usingColorSpace(.sRGB))
  }

  @Test
  func theStillComesAfterThePageShowsItsPlaceholder() async throws {
    let url = try still(.red)
    defer { try? FileManager.default.removeItem(at: url) }
    let feature = FeatureDescriptor(id: "music", title: "Music", symbol: "music.note", preview: FeaturePreview(still: url))
    let host = NSHostingView(rootView: FeaturePreviewView(feature: feature).frame(width: 400, height: 250))
    let window = NSWindow(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 400, height: 250),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    window.orderFrontRegardless()
    defer { window.orderOut(nil) }
    // Colour management shifts the red, so the test asks whether red shows, not its exact value.
    func isRed(_ color: NSColor) -> Bool { color.redComponent > color.greenComponent + 0.4 }

    // The first frame: the card with the symbol, as nothing was read on the main thread.
    let first = try shownColor(host)
    #expect(!isRed(first), "the first frame shows \(first)")
    // Then the still: the main actor is free meanwhile, as the reading isn't on it. It takes a moment alone, longer
    // while the other suites keep the main actor busy.
    let start = ContinuousClock.now
    var shown = first
    while !isRed(shown), ContinuousClock.now - start < .seconds(30) {
      try await Task.sleep(for: .milliseconds(50))
      shown = try shownColor(host)
    }
    #expect(isRed(shown), "the preview shows \(shown)")
  }
}
