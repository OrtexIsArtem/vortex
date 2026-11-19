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

  /// The preview of `feature` at the size its page shows it.
  func preview(_ feature: FeatureDescriptor) -> some View {
    FeaturePreviewView(feature: feature).frame(width: 400, height: 250)
  }

  /// A window off every display, holding `host`.
  func offScreenWindow(_ host: NSView) -> NSWindow {
    let window = NSWindow(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 400, height: 250),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    window.orderFrontRegardless()
    return window
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

  /// The colour the preview shows once `isShown` holds of it, or after 30 s: a still takes a moment to read alone,
  /// longer while the other suites keep the main actor busy, which is free meanwhile as the reading isn't on it.
  func shownColor(_ host: NSView, once isShown: (NSColor) -> Bool) async throws -> NSColor {
    let start = ContinuousClock.now
    var shown = try shownColor(host)
    while !isShown(shown), ContinuousClock.now - start < .seconds(30) {
      try await Task.sleep(for: .milliseconds(50))
      shown = try shownColor(host)
    }
    return shown
  }

  // Colour management shifts the colours, so the tests ask which one shows, not its exact value.
  func isRed(_ color: NSColor) -> Bool {
    color.redComponent > color.greenComponent + 0.4 && color.redComponent > color.blueComponent + 0.4
  }

  func isBlue(_ color: NSColor) -> Bool {
    color.blueComponent > color.greenComponent + 0.4 && color.blueComponent > color.redComponent + 0.4
  }

  @Test
  func theStillComesAfterThePageShowsItsPlaceholder() async throws {
    let url = try still(.red)
    defer { try? FileManager.default.removeItem(at: url) }
    let feature = FeatureDescriptor(id: "music", title: "Music", symbol: "music.note", preview: FeaturePreview(still: url))
    let host = NSHostingView(rootView: preview(feature))
    let window = offScreenWindow(host)
    defer { window.orderOut(nil) }

    // The first frame: the card with the symbol, as nothing was read on the main thread.
    let first = try shownColor(host)
    #expect(!isRed(first), "the first frame shows \(first)")
    // Then the still.
    let shown = try await shownColor(host, once: isRed)
    #expect(isRed(shown), "the preview shows \(shown)")
  }

  /// Straight from one feature's page to another's, as the sidebar's "About <Name>" goes while a page shows: the page
  /// keeps its views, yet the second feature's preview starts with its own symbol, never the first one's still, and
  /// then shows its own still.
  @Test
  func aPageRightAfterAnotherStartsWithItsOwnPlaceholder() async throws {
    let red = try still(.red)
    let blue = try still(.blue)
    defer {
      try? FileManager.default.removeItem(at: red)
      try? FileManager.default.removeItem(at: blue)
    }
    let music = FeatureDescriptor(
      id: "music", title: "Music", symbol: "music.note", preview: FeaturePreview(still: red)
    )
    let tasks = FeatureDescriptor(
      id: "tasks", title: "Tasks", symbol: "checkmark.square", preview: FeaturePreview(still: blue)
    )
    let host = NSHostingView(rootView: preview(music))
    let window = offScreenWindow(host)
    defer { window.orderOut(nil) }
    let musicStill = try await shownColor(host, once: isRed)
    #expect(isRed(musicStill), "Music's page shows \(musicStill)")

    host.rootView = preview(tasks)
    let first = try shownColor(host)
    #expect(!isRed(first) && !isBlue(first), "the first frame of Tasks' page shows \(first)")
    let shown = try await shownColor(host, once: isBlue)
    #expect(isBlue(shown), "Tasks' page shows \(shown)")
  }
}
