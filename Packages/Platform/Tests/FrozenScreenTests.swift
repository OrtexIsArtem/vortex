import ComposableArchitecture
import SwiftUI
import Testing

@testable import VortexPlatform

/// One frozen screen at a time, whichever feature froze it: Tasks' capture and Screen Text's never stack, even when
/// their shortcuts are the same keys. Nothing here reaches a display: a refused overlay never makes its window.
@MainActor
@Suite(.serialized)
struct FrozenScreenTests {
  /// Two captures started together both take the screen; the second to show is refused and ends as interrupted, as
  /// when another app comes to the front, so its feature cancels its capture.
  @Test
  func aSecondFrozenScreenIsRefusedAndEndsAsInterrupted() async {
    let first = ScreenOverlay()
    FrozenScreen.shown = first
    defer { FrozenScreen.shown = nil }
    let second = ScreenOverlay()
    let interrupted = LockIsolated(0)
    second.show(Color.clear, on: 0, over: nil, onEscape: {}, onReturn: {}, onInterrupted: { interrupted.withValue { $0 += 1 } })
    #expect(!second.isShown)
    #expect(FrozenScreen.shown === first)
    for _ in 0..<100 where interrupted.value == 0 {
      await Task.yield()
    }
    #expect(interrupted.value == 1)
  }

  /// While one shows, a capture is refused before it takes the screen: no second screenshot at all.
  @Test
  func aCaptureIsRefusedWhileAFrozenScreenShows() async throws {
    let overlay = ScreenOverlay()
    FrozenScreen.shown = overlay
    defer { FrozenScreen.shown = nil }
    #expect(FrozenScreen.isShown)
    await #expect(throws: ScreenCaptureError.frozenScreenShown) { try await ScreenCaptureClient.qa.captureScreenUnderPointer() }
    #expect(QALog.events.value.last { $0.client == "screenCapture" }?.detail == ["result": "refused: a frozen screen shows"])
    withExtendedLifetime(overlay) {}
  }

  /// The registry forgets an overlay that's gone, so a frozen screen never outlives its window's owner.
  @Test
  func anOverlayThatIsGoneHoldsNoFrozenScreen() {
    do {
      let gone = ScreenOverlay()
      FrozenScreen.shown = gone
    }
    #expect(!FrozenScreen.isShown)
  }
}
