import CoreGraphics
import Testing

@testable import VortexCore

/// The sizes the window takes, in exact points on every Mac.
struct WindowSizeTests {
  /// The regular window is 680×440; the catalog's and the editor's grow right to 880; Home's utilities dock grows it
  /// right by a strip as wide as the sidebar, 736.
  @Test
  func theDocksWindowIsTheRegularOneAndAStripAsWideAsTheSidebar() {
    #expect(WindowSize.regular.size == CGSize(width: 680, height: 440))
    #expect(WindowSize.large.size == CGSize(width: 880, height: 440))
    #expect(VortexMetrics.dockWidth == VortexMetrics.sidebarWidth)
    #expect(WindowSize.dock.size == CGSize(width: 680 + VortexMetrics.dockWidth, height: 440))
  }
}
