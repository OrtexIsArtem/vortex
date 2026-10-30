#if DEBUG
  import Testing
  import VortexCore
  import VortexPlatform

  @testable import VortexShell

  /// The marks QA's state lists per feature: control, sidebar dot and settings rows.
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
    func everythingSkippedMarksOnlyWhereEachFeatureShowsItsPermissions() {
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

    /// A press needs its control on screen: the window open on the tab or on Settings › Features, and not covered by
    /// keyboard cleaning's lock screen.
    @Test
    func aControlShowsOnlyInTheOpenWindowAndNeverUnderTheLockScreen() {
      var state = ShellFeature.State(features: [Self.home, Self.tasks, Self.timer])
      state.selectedTab = .feature("tasks")
      #expect(!PermissionsQA.isShowing(.tab("tasks"), in: state))
      state.openReason = .click
      #expect(PermissionsQA.isShowing(.tab("tasks"), in: state))
      #expect(!PermissionsQA.isShowing(.tab("timer"), in: state))
      #expect(!PermissionsQA.isShowing(.featureSettings, in: state))
      state.keyboardCleaning.isLocked = true
      #expect(!PermissionsQA.isShowing(.tab("tasks"), in: state))
      state.keyboardCleaning.isLocked = false
      state.selectedTab = .settings
      state.settingsSection = .general
      #expect(!PermissionsQA.isShowing(.featureSettings, in: state))
      state.settingsSection = .features
      #expect(PermissionsQA.isShowing(.featureSettings, in: state))
      state.keyboardCleaning.isLocked = true
      #expect(!PermissionsQA.isShowing(.featureSettings, in: state))
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
