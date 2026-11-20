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

  /// On a notch wider than a 14" or 16" MacBook Pro's 185 pt at its default scale, the regular window is wider, by as
  /// much as Home's notch row needs there: right of the notch, the room for the row's widget (`notchRowSide`) and the
  /// utilities button's slot, and as much left of it, so the notch stays in the window's middle. The large window and
  /// the dock's are built on it; without a notch it is 680.
  @Test
  func aWideNotchWidensTheWindowByWhatTheNotchRowNeeds() {
    let widths: [(notch: CGFloat, window: CGFloat)] = [(185, 680), (186, 680), (187, 681), (202, 696), (220, 714), (240, 734)]
    for (notch, window) in widths {
      #expect(WindowSize.regular.size(notchWidth: notch) == CGSize(width: window, height: 440), "a \(notch) pt notch")
      #expect(WindowSize.large.size(notchWidth: notch) == CGSize(width: window + 200, height: 440), "a \(notch) pt notch")
      #expect(WindowSize.dock.size(notchWidth: notch) == CGSize(width: window + 56, height: 440), "a \(notch) pt notch")
      #expect(window >= notch + 2 * (VortexMetrics.notchRowSide + VortexMetrics.hitTarget), "a \(notch) pt notch")
    }
    #expect(WindowSize.regular.size(notchWidth: nil) == WindowSize.regular.size)
  }
}
