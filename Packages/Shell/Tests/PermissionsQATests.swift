#if DEBUG
  import Testing
  import VortexCore
  import VortexPlatform

  @testable import VortexShell

  /// The marks QA's state lists per feature (S22): control, sidebar dot and settings rows.
  struct PermissionsQATests {
    static let home = FeatureDescriptor(id: "home", title: "Home", symbol: "house")
    static let tasks = FeatureDescriptor(
      id: "tasks", title: "Tasks", symbol: "checklist",
      permissionNeeds: [PermissionNeed(.screenRecording, reason: "Turns a screenshot into a new task.")]
    )
    static let timer = FeatureDescriptor(
      id: "timer", title: "Timer", symbol: "timer",
      permissionNeeds: [PermissionNeed(.notifications, reason: "Tells you when a timer ends.")]
    )

    @Test
    func everythingSkippedMarksOnlyWhereS22PutsThem() {
      let statuses: [Permission: PermissionStatus] = [
        .notifications: .notGranted, .accessibility: .notGranted, .screenRecording: .notGranted, .pasteboard: .notNeeded,
      ]
      let home = PermissionsQA.marks(of: Self.home, statuses)
      #expect(home.control == .warning)
      #expect(home.sidebar == nil)
      #expect(home.settings.isEmpty)
      let tasks = PermissionsQA.marks(of: Self.tasks, statuses)
      #expect(tasks.control == .warning)
      #expect(tasks.sidebar == .screenRecording)
      #expect(tasks.settings == [.screenRecording: .warning])
      let timer = PermissionsQA.marks(of: Self.timer, statuses)
      #expect(timer.control == nil)
      #expect(timer.sidebar == .notifications)
      #expect(timer.settings == [.notifications: .warning])
    }

    @Test
    func noMarksBeforeTheFirstReadAndNoYellowForRestart() {
      #expect(PermissionsQA.marks(of: Self.tasks, [:]) == PermissionsQA.Marks(control: nil, sidebar: nil, settings: [:]))
      let restart = PermissionsQA.marks(of: Self.tasks, [.screenRecording: .grantedAfterRestart])
      #expect(restart.control == nil)
      #expect(restart.sidebar == nil)
      #expect(restart.settings == [.screenRecording: .afterRestart])
    }
  }
#endif
