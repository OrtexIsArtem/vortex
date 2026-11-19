import AppKit
import SwiftUI
import Testing
import VortexCore

@testable import VortexShell

/// The window lays its content out from its left edge. Content wider than the window for a moment, as Home is while
/// its editor's panel waits for the window to grow, runs past the right edge and never pushes the sidebar out left.
@MainActor
struct WindowChromeLayoutTests {
  @Test
  func contentWiderThanTheWindowKeepsTheSidebarAtTheLeftEdge() throws {
    let model = WindowPresentationModel()
    model.isExpanded = true
    let size = WindowSize.regular.size
    // The sidebar, then a tab 200 pt wider than the window's room for it: Home with its editor's panel, the moment
    // before the window grows.
    let content = HStack(spacing: 0) {
      Color(red: 1, green: 0, blue: 0).frame(width: VortexMetrics.sidebarWidth)
      Color(red: 0, green: 1, blue: 0).frame(width: size.width + 200 - VortexMetrics.sidebarWidth)
    }
    let host = NSHostingView(rootView: WindowChromeView(model: model, content: AnyView(content)))
    let window = NSWindow(
      contentRect: CGRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width

    // Halfway into the sidebar's place, halfway down the window.
    let x = Int((VortexMetrics.sidebarWidth / 2) * scale)
    let y = Int((size.height / 2) * scale)
    // Colour management shifts both colours, so the test asks which one shows, not its exact value.
    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    #expect(color.redComponent > color.greenComponent + 0.3, "the sidebar's place shows \(color)")
  }
}
