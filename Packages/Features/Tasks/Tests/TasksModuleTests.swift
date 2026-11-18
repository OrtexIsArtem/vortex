import ComposableArchitecture
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureTasks

@MainActor
struct TasksModuleTests {
  /// A capture takes a screenshot of the display.
  @Test
  func tasksNeedScreenRecording() {
    #expect(TasksModule.permissionNeeds.map(\.permission) == [.screenRecording])
    #expect(TasksModule.descriptor.permissionNeeds == TasksModule.permissionNeeds)
  }

  /// Erase Data forgets the "New task" shortcut, which lives outside the data folder.
  @Test
  func erasingTasksForgetsItsShortcut() async {
    let reset = LockIsolated<[String]>([])
    await withDependencies {
      $0.hotkeyClient.reset = { hotkey in reset.withValue { $0.append(hotkey.name) } }
    } operation: {
      await TasksModule.eraseData()
    }
    #expect(reset.value == ["captureTask"])
  }
}
