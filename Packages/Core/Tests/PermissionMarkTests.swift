import Testing

@testable import VortexCore

/// Where a permission shows in a feature (S22, S40): yellow only while off, ↻ without yellow, nothing before the first
/// read or once it works.
struct PermissionMarkTests {
  @Test
  func onlyNotGrantedIsYellowAndOnlyGrantedAfterRestartIsRestart() {
    #expect(PermissionMark(nil) == nil)
    #expect(PermissionMark(.granted) == nil)
    #expect(PermissionMark(.notNeeded) == nil)
    #expect(PermissionMark(.notGranted) == .warning)
    #expect(PermissionMark(.grantedAfterRestart) == .afterRestart)
  }

  @Test
  func theSidebarDotNamesTheFirstPermissionThatIsOff() {
    let needs = [PermissionNeed(.notifications, reason: "a"), PermissionNeed(.screenRecording, reason: "b")]
    #expect(needs.firstOff(in: [:]) == nil)
    #expect(needs.firstOff(in: [.notifications: .grantedAfterRestart, .screenRecording: .granted]) == nil)
    #expect(needs.firstOff(in: [.notifications: .granted, .screenRecording: .notGranted]) == .screenRecording)
    #expect(needs.firstOff(in: [.notifications: .notGranted, .screenRecording: .notGranted]) == .notifications)
  }
}
