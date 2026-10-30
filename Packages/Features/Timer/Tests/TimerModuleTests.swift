import Testing
import VortexCore

@testable import FeatureTimer

@MainActor
struct TimerModuleTests {
  /// The notification when time is up.
  @Test
  func theTimerNeedsNotifications() {
    #expect(TimerModule.permissionNeeds.map(\.permission) == [.notifications])
    #expect(TimerModule.descriptor.permissionNeeds == TimerModule.permissionNeeds)
  }
}
