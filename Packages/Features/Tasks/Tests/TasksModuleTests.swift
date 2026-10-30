import Testing
import VortexCore

@testable import FeatureTasks

@MainActor
struct TasksModuleTests {
  /// A capture takes a screenshot of the display.
  @Test
  func tasksNeedScreenRecording() {
    #expect(TasksModule.permissionNeeds.map(\.permission) == [.screenRecording])
    #expect(TasksModule.descriptor.permissionNeeds == TasksModule.permissionNeeds)
  }
}
