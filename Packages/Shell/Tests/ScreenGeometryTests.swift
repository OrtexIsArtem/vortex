import CoreGraphics
import Testing
import VortexCore
@testable import VortexShell

struct ScreenGeometryTests {
  /// 14" MacBook Pro in its default scaling: 1512 × 982 points, 185-point notch, 32-point menu bar.
  let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

  @Test
  func notchComesFromTheUnobscuredCorners() {
    let notch = ScreenGeometry.notchRect(screenFrame: screen, topInset: 32, leftAreaWidth: 663.5, rightAreaWidth: 663.5)
    #expect(notch == CGRect(x: 663.5, y: 950, width: 185, height: 32))
  }

  @Test
  func noNotchWithoutTopInsetOrCorners() {
    #expect(ScreenGeometry.notchRect(screenFrame: screen, topInset: 0, leftAreaWidth: 663.5, rightAreaWidth: 663.5) == nil)
    #expect(ScreenGeometry.notchRect(screenFrame: screen, topInset: 32, leftAreaWidth: nil, rightAreaWidth: nil) == nil)
  }

  @Test
  func notchIsFoundOnASecondaryScreenToo() {
    let external = CGRect(x: -1512, y: 200, width: 1512, height: 982)
    let notch = ScreenGeometry.notchRect(screenFrame: external, topInset: 32, leftAreaWidth: 663.5, rightAreaWidth: 663.5)
    #expect(notch?.minX == -848.5)
    #expect(notch?.maxY == external.maxY)
  }

  @Test
  func windowHangsFromTheNotchWithShoulders() {
    let notch = CGRect(x: 663.5, y: 950, width: 185, height: 32)
    let frame = ScreenGeometry.notchWindowFrame(notch: notch, screenFrame: screen, visibleFrame: screen, size: .regular, shoulder: 10)
    #expect(frame.width == 700)
    #expect(frame.midX == notch.midX)
    #expect(frame.maxY == screen.maxY)
    #expect(frame.height == 440)
  }

  @Test
  func menuBarWindowStaysOnScreen() {
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 957)
    let icon = CGRect(x: 1490, y: 957, width: 22, height: 25)
    let frame = ScreenGeometry.menuBarWindowFrame(anchor: icon, visibleFrame: visible, size: .regular)
    #expect(frame.maxX == visible.maxX - 8)
    #expect(frame.maxY == visible.maxY - 6)
  }

  @Test
  func menuBarWindowCentersUnderTheIconWhenThereIsRoom() {
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 957)
    let icon = CGRect(x: 700, y: 957, width: 22, height: 25)
    let frame = ScreenGeometry.menuBarWindowFrame(anchor: icon, visibleFrame: visible, size: .regular)
    #expect(frame.midX == icon.midX)
  }

  /// The large window keeps the regular one's left edge, so the sidebar doesn't move, and grows right.
  @Test
  func aLargeWindowGrowsRight() {
    let notch = CGRect(x: 663.5, y: 950, width: 185, height: 32)
    let regular = ScreenGeometry.notchWindowFrame(notch: notch, screenFrame: screen, visibleFrame: screen, size: .regular, shoulder: 10)
    let large = ScreenGeometry.notchWindowFrame(notch: notch, screenFrame: screen, visibleFrame: screen, size: .large, shoulder: 10)
    #expect(large.minX == regular.minX && large.maxY == regular.maxY)
    #expect(large.width == 900 && large.height == 440)
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 957)
    let icon = CGRect(x: 700, y: 957, width: 22, height: 25)
    let under = ScreenGeometry.menuBarWindowFrame(anchor: icon, visibleFrame: visible, size: .regular)
    let wide = ScreenGeometry.menuBarWindowFrame(anchor: icon, visibleFrame: visible, size: .large)
    #expect(wide.minX == under.minX && wide.width == 880 && wide.maxY == under.maxY)
  }

  /// Where there's no room to grow right, the large window moves left just enough to stay on screen.
  @Test
  func aLargeWindowStaysOnScreen() {
    let small = CGRect(x: 0, y: 0, width: 1024, height: 640)
    let visible = CGRect(x: 0, y: 0, width: 1024, height: 615)
    let notch = CGRect(x: 419.5, y: 608, width: 185, height: 32)
    let frame = ScreenGeometry.notchWindowFrame(notch: notch, screenFrame: small, visibleFrame: visible, size: .large, shoulder: 10)
    #expect(frame.minX >= visible.minX && frame.maxX <= visible.maxX)
    #expect(frame.maxX == visible.maxX && frame.width == 900)
    let icon = CGRect(x: 1000, y: 615, width: 22, height: 25)
    let wide = ScreenGeometry.menuBarWindowFrame(anchor: icon, visibleFrame: visible, size: .large)
    #expect(wide.minX >= visible.minX + 8 && wide.maxX == visible.maxX - 8)
  }

  @Test
  func earsWidenTheNotchOnBothSides() {
    let notch = CGRect(x: 663.5, y: 950, width: 185, height: 32)
    #expect(ScreenGeometry.earsFrame(notch: notch, earWidth: 0, shoulder: 10) == notch)
    let frame = ScreenGeometry.earsFrame(notch: notch, earWidth: 60, shoulder: 10)
    #expect(frame.width == notch.width + 2 * (60 + 10))
    #expect(frame.midX == notch.midX)
  }
}
