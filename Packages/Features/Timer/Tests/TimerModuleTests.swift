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

  /// Home's row next to the notch takes the timer's widget.
  @Test
  func theTimerWidgetSitsInTheNotchRow() {
    let widgets = TimerModule.makeHomeWidgets()
    #expect(HomeWidget.problems(widgets, feature: TimerModule.id).isEmpty)
    #expect(widgets.map(\.id) == ["timer.timer"])
    #expect(widgets.first?.place == .notchRow)
  }

}
