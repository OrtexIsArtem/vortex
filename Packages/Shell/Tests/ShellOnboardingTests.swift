import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import VortexShell

/// The shell around the onboarding: entry points while blocked (S9, S43, S46, S64), the notch window giving way to a
/// page (S37), keyboard cleaning during a revoke (S38), the menu bar icon (S42) and the first read (S7).
@MainActor
struct ShellOnboardingTests {
  let clock = TestClock()
  let presented = LockIsolated<[OpenReason]>([])
  let dismissals = LockIsolated(0)
  let onboardingWindow = LockIsolated<[String]>([])
  let quits = LockIsolated(0)

  func makeStore(
    progress: OnboardingProgress = .finished,
    required: Set<Permission> = [],
    statuses: [Permission: PermissionStatus]? = OnboardingNeeds.allOff
  ) -> TestStoreOf<ShellFeature> {
    @Shared(.permissionStatuses) var shared
    $shared.withLock { $0 = statuses ?? [:] }
    var state = ShellFeature.State(features: OnboardingNeeds.all + [.shelf], onboarding: progress)
    state.requiredPermissions = required
    state.onboarding.catalog = state.permissionCatalog
    let store = TestStore(initialState: state) {
      ShellFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.windowClient.present = { [presented] reason in presented.withValue { $0.append(reason) } }
      $0.windowClient.dismiss = { [dismissals] in dismissals.withValue { $0 += 1 } }
      $0.windowClient.setMenuBarIconVisible = { _ in }
      $0.windowClient.setAcceptsFiles = { _ in }
      $0.windowClient.holdKeyboard = { _ in }
      $0.settingsClient.save = { _ in }
      $0.featuresClient.setEnabled = { _, _ in }
      $0.onboardingProgress.save = { _ in }
      $0.onboardingWindow.present = { [onboardingWindow] mode, activate in
        onboardingWindow.withValue { $0.append(mode.rawValue + (activate ? "+activate" : "")) }
      }
      $0.onboardingWindow.hide = { [onboardingWindow] _ in onboardingWindow.withValue { $0.append("hide") } }
      $0.permissionsClient.refresh = {}
      $0.permissionsClient.setFrequentChecks = { _ in }
      $0.launchAtLoginClient.status = { .disabled }
      $0.systemClient.quit = { [quits] in quits.withValue { $0 += 1 } }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    return store
  }

  func effectsRun() async {
    try? await Task.sleep(for: .milliseconds(50))
  }

  // MARK: - Blocked (S9, S43, S46)

  @Test
  func whileBlockedEveryEntryPointOpensTheBlockingPageAndNeverTheNotchWindow() async {
    let store = makeStore(required: [.accessibility])
    #expect(store.state.isBlocked)
    func entry(_ action: ShellFeature.Action) async {
      await store.send(action)
      await store.receive(\.onboarding.blockedEntry)
      #expect(store.state.onboarding.presentation == .single(.init(permission: .accessibility, kind: .blocked)))
      #expect(store.state.openReason == nil)
      await store.send(.onboarding(.closeTapped))
    }
    await entry(.openHotkeyPressed)
    await entry(.window(.menuBarIconClicked))
    await entry(.menuOpenTapped)
    await entry(.menuSettingsTapped)
    await entry(.featureHotkeyPressed("timer"))
    await entry(.window(.notchClicked(feature: nil)))
    // A file dragged onto the notch too (S43).
    await entry(.window(.fileDragEnteredNotch))
    // A hover shows the page without activating Vortex (S46).
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .milliseconds(300))
    await store.receive(\.hoverDelayElapsed)
    await store.receive(\.onboarding.blockedEntry)
    #expect(store.state.openReason == nil)
    await effectsRun()
    #expect(presented.value.isEmpty)
    #expect(onboardingWindow.value.filter { $0 != "hide" } == Array(repeating: "window+activate", count: 7) + ["window"])
    // «Вийти з Vortex» still works.
    await store.send(.quitButtonTapped)
    await effectsRun()
    #expect(quits.value == 1)
  }

  @Test
  func aRevokeWhileTheNotchWindowIsOpenClosesItAndOpensTheBlockingPage() async {
    let store = makeStore(required: [.accessibility], statuses: OnboardingNeeds.allOn)
    #expect(!store.state.isBlocked)
    await store.send(.openHotkeyPressed)
    #expect(store.state.openReason == .hotkey)
    var revoked = OnboardingNeeds.allOn
    revoked[.accessibility] = .notGranted
    await store.send(.permissionStatusesChanged(revoked))
    #expect(store.state.openReason == nil)
    await store.receive(\.onboarding.statusesChanged)
    #expect(store.state.appBlocked)
    await store.receive(\.onboarding.blocked)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .accessibility, kind: .blocked)))
    // Granted again: the page closes 1.5 s after ✓, and the notch window opens again.
    await store.send(.permissionStatusesChanged(OnboardingNeeds.allOn))
    #expect(!store.state.appBlocked)
    await clock.advance(by: .milliseconds(1_500))
    await store.receive(\.onboarding.singleCloseElapsed)
    #expect(store.state.onboarding.presentation == .hidden)
    await store.send(.openHotkeyPressed)
    #expect(store.state.openReason == .hotkey)
  }

  @Test
  func entryPointsWaitForTheFirstStatusRead() async {
    let store = makeStore(required: [.accessibility], statuses: nil)
    await store.send(.openHotkeyPressed)
    #expect(store.state.openReason == nil)
    #expect(store.state.pendingEntry == .hotkey)
    // The first read says not blocked: the window opens as asked.
    await store.send(.permissionStatusesChanged(OnboardingNeeds.allOn))
    #expect(store.state.openReason == .hotkey)
    #expect(store.state.pendingEntry == nil)

    let blocked = makeStore(required: [.accessibility], statuses: nil)
    await blocked.send(.menuOpenTapped)
    await blocked.send(.permissionStatusesChanged(OnboardingNeeds.allOff))
    await blocked.receive(\.onboarding.launched)
    #expect(blocked.state.openReason == nil)
    #expect(blocked.state.onboarding.presentation == .single(.init(permission: .accessibility, kind: .blocked)))
  }

  // MARK: - Pages (S7, S37, S65)

  @Test
  func aPageRequestClosesTheNotchWindowFirst() async {
    let store = makeStore()
    await store.send(.openHotkeyPressed)
    await store.send(.permissionPageRequested(.screenRecording))
    await store.receive(\.onboarding.pageRequested)
    #expect(store.state.openReason == nil)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .screenRecording, kind: .request)))
    await effectsRun()
    #expect(dismissals.value == 1)
  }

  @Test
  func theFirstReadShowsAnUnfinishedOnboardingAtItsSavedPage() async {
    let store = makeStore(progress: .at(.permission(.screenRecording)), statuses: nil)
    await store.send(.permissionStatusesChanged(OnboardingNeeds.allOff))
    await store.receive(\.onboarding.launched)
    #expect(store.state.onboarding.presentation == .flow)
    #expect(store.state.onboarding.page == .permission(.screenRecording))
  }

  @Test
  func theOnboardingFollowsFeaturesTurnedOnAndOff() async {
    let store = makeStore(progress: .at(.welcome))
    await store.send(.featureEnabledChanged("tasks", isEnabled: false))
    #expect(!store.state.onboarding.pages.contains(.permission(.screenRecording)))
    await store.send(.featureEnabledChanged("tasks", isEnabled: true))
    #expect(store.state.onboarding.pages.contains(.permission(.screenRecording)))
  }

  // MARK: - Keyboard cleaning (S38)

  @Test
  func losingAccessibilityDuringTheLockEndsItAndAnotherRequiredLossWaitsForTheKeyboard() async {
    var granted = OnboardingNeeds.allOn
    let store = makeStore(required: [.screenRecording], statuses: granted)
    store.dependencies.keyboardLockClient.lock = { true }
    store.dependencies.keyboardLockClient.unlock = {}
    await store.send(.openHotkeyPressed)
    await store.send(.keyboardCleaning(.startTapped))
    #expect(store.state.keyboardCleaning.isLocked)

    // Another required permission goes: the lock screen stays, nothing opens.
    granted[.screenRecording] = .notGranted
    await store.send(.permissionStatusesChanged(granted))
    #expect(store.state.keyboardCleaning.isLocked)
    #expect(store.state.openReason == .hotkey)
    #expect(store.state.onboarding.presentation == .hidden)
    // «Увімкнути клавіатуру»: the window closes, and only now Vortex is blocked.
    await store.send(.keyboardCleaning(.stopTapped))
    #expect(store.state.openReason == nil)
    await store.receive(\.onboarding.blocked)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .screenRecording, kind: .blocked)))

    // Accessibility going during a lock ends it at once, and no page opens.
    let second = makeStore(statuses: OnboardingNeeds.allOn)
    second.dependencies.keyboardLockClient.lock = { true }
    second.dependencies.keyboardLockClient.unlock = {}
    await second.send(.openHotkeyPressed)
    await second.send(.keyboardCleaning(.startTapped))
    var lost = OnboardingNeeds.allOn
    lost[.accessibility] = .notGranted
    await second.send(.permissionStatusesChanged(lost))
    await second.receive(\.keyboardCleaning.accessLost)
    #expect(!second.state.keyboardCleaning.isLocked)
    #expect(second.state.onboarding.presentation == .hidden)
  }

  @Test
  func keyboardCleaningWithoutAccessOpensThePageAfterClosingTheNotchWindow() async {
    let store = makeStore()
    await store.send(.openHotkeyPressed)
    await store.send(.keyboardCleaning(.startTapped))
    await store.receive(\.keyboardCleaning.delegate)
    await store.receive(\.onboarding.pageRequested)
    #expect(store.state.openReason == nil)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .accessibility, kind: .request)))
  }

  // MARK: - The menu bar icon (S42)

  @Test
  func theMenuBarIconShowsWhileTheOnboardingIsUnfinishedOrVortexIsBlocked() {
    var settings = ShellSettings()
    settings.showMenuBarIcon = false
    var unfinished = ShellFeature.State(settings: settings, features: OnboardingNeeds.all)
    #expect(unfinished.isMenuBarIconVisible)
    unfinished.onboarding.progress.completed = true
    #expect(!unfinished.isMenuBarIconVisible)
    @Shared(.permissionStatuses) var shared
    $shared.withLock { $0 = OnboardingNeeds.allOff }
    unfinished.requiredPermissions = [.accessibility]
    #expect(unfinished.isMenuBarIconVisible)
  }

  @Test
  func donesHintNamesOnlyWhatOpensVortexHere() {
    var settings = ShellSettings()
    settings.openOnHover = true
    settings.showMenuBarIcon = true
    var state = ShellFeature.State(settings: settings, features: OnboardingNeeds.all)
    #expect(state.doneHint == .init(hoverNotch: true, menuBarIcon: true))
    state.everyScreenHasNotch = false
    #expect(state.doneHint.hoverNotch == false)
    #expect(state.doneHint.menuBarIcon)
  }
}
