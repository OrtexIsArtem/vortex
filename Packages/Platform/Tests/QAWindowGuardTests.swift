#if DEBUG
  import AppKit
  import Testing

  @testable import VortexPlatform

  /// Stands in for a window: the guard's checks without anything reaching a display.
  @MainActor
  final class StandInWindow: QAGuardedWindow {
    var isVisible: Bool
    var frame: NSRect
    var occlusionState: NSWindow.OcclusionState
    private(set) var isOrderedOut = false

    init(isVisible: Bool = true, frame: NSRect, occlusionState: NSWindow.OcclusionState = []) {
      self.isVisible = isVisible
      self.frame = frame
      self.occlusionState = occlusionState
    }

    func orderOut(_ sender: Any?) {
      isOrderedOut = true
      isVisible = false
    }

    func setFrameOrigin(_ point: NSPoint) {
      frame.origin = point
    }
  }

  /// The QA window guard: any window of a run that shows on a display is a violation and is ordered out, wherever it
  /// came from: a window placed before the guard was installed, one AppKit kept on a display, one moved there.
  @MainActor
  struct QAWindowGuardTests {
    let display = CGRect(x: 0, y: 0, width: 1_440, height: 900)

    /// The guard's violations for a stand-in window at `frame`.
    func violations(at frame: CGRect) -> [QAEvent] {
      let described = "\(Int(frame.minX)) \(Int(frame.minY)) \(Int(frame.width))×\(Int(frame.height))"
      return QALog.violations.value.filter { $0.detail["class"] == "StandInWindow" && $0.detail["frame"] == described }
    }

    @Test
    func aWindowOnADisplayIsAViolationAndIsOrderedOutAndMovedOff() {
      // Where the onboarding window landed in the slip: its title bar kept on the main display.
      let landed = CGRect(x: 0, y: 63, width: 560, height: 620)
      let window = StandInWindow(frame: landed)
      QAWindowGuard.check(window, displays: [display])
      #expect(window.isOrderedOut)
      #expect(!display.intersects(window.frame))
      #expect(window.frame.size == landed.size)
      #expect(violations(at: landed).count == 1)
    }

    @Test
    func aWindowThatReportsItselfVisibleIsAViolationWhereverItsFrameIs() {
      let window = StandInWindow(frame: CGRect(x: -5_000, y: -5_000, width: 340, height: 300), occlusionState: .visible)
      QAWindowGuard.check(window, displays: [display])
      #expect(window.isOrderedOut)
    }

    @Test
    func aWindowOffTheDisplaysOrHiddenIsLeftAlone() {
      let offscreen = StandInWindow(frame: CGRect(x: -2_560, y: -2_620, width: 560, height: 620))
      QAWindowGuard.check(offscreen, displays: [display])
      #expect(!offscreen.isOrderedOut)
      #expect(violations(at: offscreen.frame).isEmpty)

      let hidden = StandInWindow(isVisible: false, frame: CGRect(x: 100, y: 100, width: 560, height: 620))
      QAWindowGuard.check(hidden, displays: [display])
      #expect(!hidden.isOrderedOut)
      #expect(violations(at: hidden.frame).isEmpty)
    }

    @Test
    func aWindowOnAnyOfSeveralDisplaysCounts() {
      let second = CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080)
      let window = StandInWindow(frame: CGRect(x: 2_000, y: 400, width: 560, height: 620))
      #expect(QAWindowGuard.isOnDisplay(window, displays: [display, second]))
      #expect(!QAWindowGuard.isOnDisplay(window, displays: [display]))
    }
  }
#endif
