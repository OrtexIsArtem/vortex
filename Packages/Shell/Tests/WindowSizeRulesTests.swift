import Testing

@testable import VortexShell

struct WindowSizeRulesTests {
  /// The window shrinking away from a still pointer leaves it outside: that is no leave.
  @Test
  func shrinkingUnderAStillPointerIsNotALeave() {
    #expect(!WindowSizeRules.closesOnPointerLeave(after: .shrink, pointerMoved: false))
    #expect(WindowSizeRules.closesOnPointerLeave(after: .shrink, pointerMoved: true))
    #expect(WindowSizeRules.closesOnPointerLeave(after: nil, pointerMoved: false))
  }
}
