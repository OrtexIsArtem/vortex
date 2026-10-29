#if DEBUG
  import ComposableArchitecture
  import Foundation
  import Testing
  import VortexCore
  import VortexPlatform

  @testable import VortexShell

  /// QA's `onboarding press=…` presses only what the user could: a button that doesn't show is refused.
  @MainActor
  struct OnboardingQATests {
    let windowCalls = CallLog()

    func makeStore(
      progress: OnboardingProgress,
      presentation: OnboardingFeature.Presentation,
      statuses: [Permission: PermissionStatus] = OnboardingNeeds.allOff
    ) -> StoreOf<ShellFeature> {
      @Shared(.permissionStatuses) var shared
      $shared.withLock { $0 = statuses }
      var state = ShellFeature.State(features: OnboardingNeeds.all, onboarding: progress)
      state.onboarding.presentation = presentation
      return Store(initialState: state) {
        ShellFeature()
      } withDependencies: {
        $0.onboardingProgress.save = { _ in }
        $0.onboardingWindow.present = { [windowCalls] mode, _ in windowCalls.record(mode.rawValue) }
        $0.onboardingWindow.hide = { [windowCalls] _ in windowCalls.record("hide") }
        $0.permissionsClient.setFrequentChecks = { _ in }
        $0.systemClient.relaunch = {}
      }
    }

    @Test
    func restartIsRefusedWhereNoRestartShows() {
      // An onboarding page with nothing waiting for a relaunch: no "Restart now", no "Restart to check".
      let flow = makeStore(progress: .at(.permission(.accessibility)), presentation: .flow(.window))
      #expect(throws: QAError.self) { try OnboardingQA.press("restart", store: flow) }
      #expect(throws: QAError.self) { try OnboardingQA.press("restartNow", store: flow) }
      // A single page whose permission is simply off: Close only.
      let single = makeStore(
        progress: .finished,
        presentation: .single(.init(permission: .accessibility, kind: .request), .window)
      )
      #expect(throws: QAError.self) { try OnboardingQA.press("restart", store: single) }
      #expect(!single.onboarding.isRelaunching)
    }

    @Test
    func laterIsRefusedUnlessTheGrantWaitsForARelaunch() async throws {
      let single = makeStore(
        progress: .finished,
        presentation: .single(.init(permission: .screenRecording, kind: .request), .window)
      )
      #expect(throws: QAError.self) { try OnboardingQA.press("later", store: single) }
      // Granted for after a relaunch: "Later" shows, and it closes the page.
      let waiting = makeStore(
        progress: .finished,
        presentation: .single(.init(permission: .screenRecording, kind: .request), .window),
        statuses: [.screenRecording: .grantedAfterRestart]
      )
      try OnboardingQA.press("later", store: waiting)
      #expect(waiting.onboarding.presentation == .hidden)
      #expect(await windowCalls.next() == "hide")
    }

    @Test
    func escapeIsRefusedOutsideASinglePage() {
      let flow = makeStore(progress: .at(.basics), presentation: .flow(.window))
      #expect(throws: QAError.self) { try OnboardingQA.press("escape", store: flow) }
    }
  }
#endif
