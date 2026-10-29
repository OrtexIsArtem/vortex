import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import VortexShell

extension OnboardingProgress {
  /// An onboarding the user finished.
  static var finished: OnboardingProgress {
    var progress = OnboardingProgress()
    progress.completed = true
    progress.page = OnboardingPage.done.id
    return progress
  }

  static func at(_ page: OnboardingPage) -> OnboardingProgress {
    var progress = OnboardingProgress()
    progress.page = page.id
    return progress
  }
}

/// Features as they declare their needs; ids as in the app. "secrets" also brings a step in some tests.
enum OnboardingNeeds {
  static let home = FeatureDescriptor(id: "home", title: "Home", symbol: "house")
  static let timer = FeatureDescriptor(
    id: "timer", title: "Timer", symbol: "timer",
    permissionNeeds: [PermissionNeed(.notifications, reason: "Tells you when a timer ends.")]
  )
  static let tasks = FeatureDescriptor(
    id: "tasks", title: "Tasks", symbol: "checklist",
    permissionNeeds: [PermissionNeed(.screenRecording, reason: "Turns a screenshot into a new task.")]
  )
  static let clipboard = FeatureDescriptor(
    id: "clipboard", title: "Clipboard", symbol: "doc.on.clipboard",
    permissionNeeds: [PermissionNeed(.pasteboard, reason: "Keeps your clipboard history.")]
  )
  static let keys = FeatureDescriptor(
    id: "secrets", title: "Keys", symbol: "key.horizontal",
    permissionNeeds: [PermissionNeed(.notifications, reason: "Shows Claude's key requests when the window is closed.")]
  )
  static let all = [home, timer, tasks, clipboard, keys]

  static let allOff = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, PermissionStatus.notGranted) })
  static let allOn = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, PermissionStatus.granted) })
}

@MainActor
struct OnboardingFeatureTests {
  let clock = TestClock()
  let saved = LockIsolated<[OnboardingProgress]>([])
  /// "window", "window+activate", "panel", "panelHidden", "hide", "hide+front", in order.
  let windowCalls = LockIsolated<[String]>([])
  let relaunches = LockIsolated(0)
  let frequentChecks = LockIsolated<[Bool]>([])
  let loginItem = LockIsolated<[String]>([])
  let mac = SimulatedPermissions()

  func makeStore(
    progress: OnboardingProgress = OnboardingProgress(),
    features: [FeatureDescriptor] = OnboardingNeeds.all,
    required: Set<Permission> = [],
    steps: [FeatureID] = [],
    statuses: [Permission: PermissionStatus]? = OnboardingNeeds.allOff,
    appliesLoginItem: Bool = false
  ) -> TestStoreOf<OnboardingFeature> {
    write(statuses ?? [:])
    var state = OnboardingFeature.State(progress: progress)
    state.catalog = PermissionCatalog(features: features, required: required)
    state.steps = steps
    state.ownBundleID = "vortex"
    state.appliesLoginItem = appliesLoginItem
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.onboardingProgress.save = { [saved] progress in saved.withValue { $0.append(progress) } }
      $0.onboardingWindow.present = { [windowCalls] mode, activate in
        windowCalls.withValue { $0.append(mode.rawValue + (activate ? "+activate" : "")) }
      }
      $0.onboardingWindow.hide = { [windowCalls] restoreFront in
        windowCalls.withValue { $0.append(restoreFront ? "hide+front" : "hide") }
      }
      $0.permissionsClient = .simulated(mac)
      $0.permissionsClient.setFrequentChecks = { [frequentChecks] isOn in frequentChecks.withValue { $0.append(isOn) } }
      $0.systemClient.relaunch = { [relaunches] in relaunches.withValue { $0 += 1 } }
      $0.launchAtLoginClient.status = { .disabled }
      $0.launchAtLoginClient.enableOnFirstLaunch = { [loginItem] in loginItem.withValue { $0.append("firstLaunch") } }
      $0.launchAtLoginClient.setEnabled = { [loginItem] isOn in
        loginItem.withValue { $0.append("set:\(isOn)") }
        return isOn ? .enabled : .disabled
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    return store
  }

  /// What macOS says, as the shell writes it.
  func write(_ statuses: [Permission: PermissionStatus]) {
    @Shared(.permissionStatuses) var shared
    $shared.withLock { $0 = statuses }
  }

  /// The shell writes new statuses and tells the onboarding.
  func change(_ store: TestStoreOf<OnboardingFeature>, _ change: (inout [Permission: PermissionStatus]) -> Void) async {
    @Shared(.permissionStatuses) var shared
    let old = shared
    $shared.withLock { change(&$0) }
    await store.send(.statusesChanged(old: old))
  }

  /// Waits out the 300 ms the navigation buttons ignore after a page change (S70).
  func settle(_ store: TestStoreOf<OnboardingFeature>) async {
    await clock.advance(by: .milliseconds(300))
    await store.receive(\.navigationUnlocked)
  }

  /// Lets effects that only call clients run.
  func effectsRun() async {
    try? await Task.sleep(for: .milliseconds(50))
  }

  func go(_ store: TestStoreOf<OnboardingFeature>, _ action: OnboardingFeature.Action) async {
    await store.send(action)
    await settle(store)
  }

  // MARK: - When the window shows (S7, S8, S21, S71)

  @Test
  func aFreshInstallShowsWelcomeAtLaunchAndChecksEverySecondWhileItShows() async {
    let store = makeStore()
    await store.send(.launched)
    #expect(store.state.presentation == .flow)
    #expect(store.state.page == .welcome)
    #expect(store.state.mode == "window")
    await effectsRun()
    #expect(windowCalls.value == ["window+activate"])
    #expect(frequentChecks.value == [true])
  }

  @Test
  func aCompletedOnboardingShowsNothingAtLaunch() async {
    let store = makeStore(progress: .finished)
    await store.send(.launched)
    #expect(store.state.presentation == .hidden)
    #expect(windowCalls.value.isEmpty)
  }

  @Test
  func everyPageChangeIsSavedAtOnceAndTheNextLaunchResumesThere() async {
    let store = makeStore()
    await store.send(.launched)
    await go(store, .getStartedTapped)
    #expect(store.state.page == .basics)
    #expect(saved.value.last?.page == "basics")

    // A relaunch, or a forced quit and a new launch, comes back to the saved page.
    let next = makeStore(progress: saved.value.last!)
    await next.send(.launched)
    #expect(next.state.page == .basics)
    #expect(next.state.presentation == .flow)
  }

  @Test
  func aSavedPageThatNoLongerExistsResumesAtTheNextPageInOrder() async {
    // Tasks was turned off, so there is no Screen Recording page any more.
    let store = makeStore(
      progress: .at(.permission(.screenRecording)),
      features: [OnboardingNeeds.home, OnboardingNeeds.timer, OnboardingNeeds.clipboard]
    )
    #expect(store.state.page == .permission(.pasteboard))
    let noneLeft = makeStore(progress: .at(.permission(.screenRecording)), features: [OnboardingNeeds.home])
    #expect(noneLeft.state.page == .done)
    let garbage = makeStore(progress: .at(.welcome))
    garbage.dependencies.onboardingProgress.save = { _ in }
    #expect(OnboardingPage(id: "nonsense") == nil)
  }

  @Test
  func pagesComeInOrderAndOnlyForWhatEnabledFeaturesNeed() {
    let store = makeStore(steps: ["secrets"])
    #expect(store.state.pages == [
      .welcome, .basics, .permission(.accessibility), .permission(.screenRecording), .permission(.pasteboard),
      .step("secrets"), .done,
    ])
    // A permission macOS doesn't ask for here has no page and no row (S1).
    write([.notifications: .granted, .accessibility: .granted, .screenRecording: .granted, .pasteboard: .notNeeded])
    #expect(!store.state.pages.contains(.permission(.pasteboard)))
    #expect(store.state.doneRows == [.notifications, .accessibility, .screenRecording])
  }

  // MARK: - Skip and Next (S19, S72, S78)

  @Test
  func skipAndNextFollowTheStatusesOnThePage() async {
    let store = makeStore(progress: .at(.basics), statuses: nil)
    // Before the first read: no checkbox state, no Skip, no Next (S72).
    #expect(store.state.rowState(.notifications) == .unknown)
    #expect(store.state.buttons == .init(nextVisible: false, nextEnabled: false, skipVisible: false))

    write(OnboardingNeeds.allOff)
    #expect(store.state.buttons == .init(nextVisible: true, nextEnabled: false, skipVisible: true))
    write([.notifications: .granted])
    #expect(store.state.buttons == .init(nextVisible: true, nextEnabled: true, skipVisible: false))
  }

  @Test
  func aRequiredPermissionThatIsOffHasNoSkipAndADisabledNext() {
    let store = makeStore(progress: .at(.permission(.accessibility)), required: [.accessibility])
    #expect(store.state.isRequiredMissing(.accessibility))
    #expect(store.state.buttons == .init(nextVisible: true, nextEnabled: false, skipVisible: false))
    write([.accessibility: .granted])
    #expect(!store.state.isRequiredMissing(.accessibility))
    #expect(store.state.buttons == .init(nextVisible: true, nextEnabled: true, skipVisible: false))
  }

  @Test
  func aGrantThatWaitsForARelaunchCountsAsOnAndOffersRestartNow() {
    let store = makeStore(progress: .at(.permission(.screenRecording)), statuses: [.screenRecording: .grantedAfterRestart])
    #expect(store.state.rowState(.screenRecording) == .afterRestart)
    #expect(store.state.buttons == .init(nextVisible: true, nextEnabled: true, skipVisible: false))
    #expect(store.state.showsRestartNow)
  }

  @Test
  func basicsWithoutNotificationsHasOnlyNext() {
    let store = makeStore(progress: .at(.basics), features: [OnboardingNeeds.home, OnboardingNeeds.tasks])
    #expect(store.state.rows(on: .basics).isEmpty)
    #expect(store.state.buttons == .init(nextVisible: true, nextEnabled: true, skipVisible: false))
  }

  @Test
  func aFeatureStepOffersSkipUntilTheFeatureMarksItDoneThenOnlyNext() {
    let store = makeStore(progress: .at(.step("secrets")), steps: ["secrets"])
    #expect(store.state.buttons == .init(nextVisible: false, nextEnabled: false, skipVisible: true))
    @Shared(.onboardingStepsDone) var done
    $done.withLock { _ = $0.insert("secrets") }
    #expect(store.state.buttons == .init(nextVisible: true, nextEnabled: true, skipVisible: false))
  }

  @Test
  func welcomeAndDoneHaveOnlyTheirOwnButton() {
    let welcome = makeStore()
    #expect(welcome.state.buttons == .init(nextVisible: false, nextEnabled: false, skipVisible: false))
    let done = makeStore(progress: .at(.done))
    #expect(done.state.buttons == .init(nextVisible: false, nextEnabled: false, skipVisible: false))
  }

  @Test
  func skipAndNextWalkThePagesInOrderAndIgnoreClicksForAMomentAfterEachChange() async {
    let store = makeStore(steps: ["secrets"])
    await store.send(.launched)
    await store.send(.getStartedTapped)
    // Within 300 ms of the change, buttons do nothing (S70).
    await store.send(.skipTapped)
    #expect(store.state.page == .basics)
    await settle(store)
    await go(store, .skipTapped)
    #expect(store.state.page == .permission(.accessibility))
    await go(store, .skipTapped)
    await go(store, .skipTapped)
    #expect(store.state.page == .permission(.pasteboard))
    // Next is disabled while the permission is off.
    await store.send(.nextTapped)
    #expect(store.state.page == .permission(.pasteboard))
    await go(store, .skipTapped)
    #expect(store.state.page == .step("secrets"))
    await go(store, .skipTapped)
    #expect(store.state.page == .done)
  }

  // MARK: - Turn on (S4, S13, S70)

  @Test
  func turnOnAsksMacOSOnceUntilTheStatusChangesOrTwoSecondsPass() async {
    let store = makeStore(progress: .at(.permission(.accessibility)))
    await store.send(.launched)
    await store.send(.turnOnTapped(.accessibility))
    await store.send(.turnOnTapped(.accessibility))
    await clock.advance(by: .milliseconds(10))
    #expect(mac.state.events == [.prompt(.accessibility)])
    await clock.advance(by: .seconds(2))
    await store.receive(\.turnOnUnlocked)
    #expect(!store.state.turnOnIgnored.contains(.accessibility))
    // A click on a checkbox that is on does nothing (S2).
    write([.accessibility: .granted])
    await store.send(.turnOnTapped(.accessibility))
    #expect(!store.state.turnOnIgnored.contains(.accessibility))
  }

  @Test
  func theNotificationsHintShowsAfterTurnOnUntilTheStatusChangesOr15Seconds() async {
    let store = makeStore(progress: .at(.basics))
    await store.send(.launched)
    await store.send(.turnOnTapped(.notifications))
    #expect(store.state.isNotificationHintVisible)
    #expect(store.state.turnOnIgnored.contains(.notifications))
    await clock.advance(by: .seconds(14))
    #expect(store.state.isNotificationHintVisible)
    await clock.advance(by: .seconds(1))
    await store.receive(\.notificationHintExpired)
    #expect(!store.state.isNotificationHintVisible)

    await store.send(.turnOnUnlocked(.notifications))
    await store.send(.turnOnTapped(.notifications))
    await change(store) { $0[.notifications] = .granted }
    #expect(!store.state.isNotificationHintVisible)
    #expect(!store.state.turnOnIgnored.contains(.notifications))
  }

  // MARK: - Pasteboard and restarts (S16, S18, S20, S68)

  @Test
  func openingThePasteboardPaneMarksItCheckedAfterRestartAndEnablesNext() async {
    let store = makeStore(progress: .at(.permission(.pasteboard)))
    await store.send(.launched)
    await store.send(.turnOnTapped(.pasteboard))
    #expect(store.state.rowState(.pasteboard) == .afterRestart)
    #expect(store.state.buttons.nextEnabled)
    #expect(saved.value.last?.pendingChecks == [.pasteboard])
    #expect(store.state.finishRestarts)
  }

  @Test
  func restartAndStartRelaunchesOnceThenDoneShowsRealStatesAndStarts() async {
    let store = makeStore(progress: .at(.done), statuses: [
      .notifications: .granted, .accessibility: .granted, .screenRecording: .grantedAfterRestart, .pasteboard: .notNeeded,
    ])
    await store.send(.launched)
    #expect(store.state.finishRestarts)
    await store.send(.finishTapped)
    await store.finish(timeout: .seconds(1))
    #expect(relaunches.value == 1)
    #expect(saved.value.last?.restarted == true)
    #expect(saved.value.last?.completed == false)
    #expect(saved.value.last?.page == "done")

    // After the relaunch: Done again, not completed, and the button no longer restarts, even if something still waits.
    var after = saved.value.last!
    after.pendingChecks = [.pasteboard]
    let relaunched = makeStore(progress: after, statuses: [.screenRecording: .grantedAfterRestart])
    await relaunched.send(.launched)
    #expect(relaunched.state.page == .done)
    #expect(relaunched.state.progress.pendingChecks.isEmpty)
    #expect(!relaunched.state.finishRestarts)
    #expect(!relaunched.state.showsRestartNow)
    await relaunched.send(.finishTapped)
    #expect(relaunched.state.progress.completed)
    #expect(relaunched.state.presentation == .hidden)
    #expect(relaunches.value == 1)
  }

  @Test
  func restartNowKeepsThePageAndQuitAndReopenResumesThere() async {
    let store = makeStore(progress: .at(.permission(.screenRecording)), statuses: [.screenRecording: .grantedAfterRestart])
    await store.send(.launched)
    await store.send(.restartTapped)
    await store.finish(timeout: .seconds(1))
    #expect(relaunches.value == 1)
    #expect(saved.value.last?.page == "permission:screenRecording")
    #expect(saved.value.last?.restarted == true)

    // System Settings' own Quit & Reopen: Vortex starts again at the same page, with fresh statuses.
    var reopened = OnboardingProgress.at(.permission(.pasteboard))
    reopened.pendingChecks = [.pasteboard]
    let store2 = makeStore(progress: reopened, statuses: [.pasteboard: .granted])
    await store2.send(.launched)
    #expect(store2.state.page == .permission(.pasteboard))
    #expect(store2.state.rowState(.pasteboard) == .on)
    #expect(store2.state.progress.restarted)
  }

  // MARK: - Done (S18, S53, S77)

  @Test
  func doneShowsARowPerNeededPermissionAndASkippedRowOpensItsPageWhichReturnsToDone() async {
    let store = makeStore(progress: .at(.done), statuses: [
      .notifications: .notGranted, .accessibility: .granted, .screenRecording: .grantedAfterRestart, .pasteboard: .notGranted,
    ])
    await store.send(.launched)
    #expect(store.state.doneRows.map(store.state.rowState) == [.off, .on, .afterRestart, .off])
    await go(store, .doneRowTapped(.pasteboard))
    #expect(store.state.page == .permission(.pasteboard))
    #expect(store.state.progress.returnToDone)
    await go(store, .skipTapped)
    #expect(store.state.page == .done)
    #expect(!store.state.progress.returnToDone)

    // The notifications row opens Basics, which returns to Done as well (S77).
    await go(store, .doneRowTapped(.notifications))
    #expect(store.state.page == .basics)
    await go(store, .skipTapped)
    #expect(store.state.page == .done)
  }

  @Test
  func doneWaitsForEveryRequiredPermission() async {
    let store = makeStore(progress: .at(.done), required: [.accessibility])
    await store.send(.launched)
    await settle(store)
    #expect(!store.state.finishEnabled)
    await store.send(.finishTapped)
    #expect(!store.state.progress.completed)
    write([.notifications: .notGranted, .accessibility: .granted])
    #expect(store.state.finishEnabled)
  }

  // MARK: - Closing and continuing (S10, S69, S80)

  @Test
  func closingBeforeCompletionKeepsTheProgressAndContinueSetupReopensAtTheSavedPage() async {
    let store = makeStore(progress: .at(.permission(.accessibility)))
    await store.send(.launched)
    await store.send(.closeTapped)
    #expect(store.state.presentation == .hidden)
    #expect(store.state.progress.page == "permission:accessibility")
    #expect(!store.state.progress.completed)
    // A request now shows a single page, and the saved page stays (S52).
    await store.send(.pageRequested(.screenRecording, .request))
    #expect(store.state.presentation == .single(.init(permission: .screenRecording, kind: .request)))
    // «Продовжити налаштування» replaces it with the onboarding at the saved page (S80).
    await store.send(.continueSetupTapped)
    #expect(store.state.presentation == .flow)
    #expect(store.state.page == .permission(.accessibility))
    await effectsRun()
    #expect(windowCalls.value == ["window+activate", "hide", "window+activate", "window+activate"])
  }

  // MARK: - The single page (S11, S24, S49–S52, S55)

  @Test
  func aRequestWhileTheOnboardingShowsBringsItForwardWithoutJumping() async {
    let store = makeStore(progress: .at(.basics))
    await store.send(.launched)
    await store.send(.pageRequested(.screenRecording, .request))
    #expect(store.state.presentation == .flow)
    #expect(store.state.page == .basics)
    await effectsRun()
    #expect(windowCalls.value == ["window+activate", "window+activate"])
  }

  @Test
  func aSinglePageClosesSecondsAfterTheGrant() async {
    let store = makeStore(progress: .finished)
    await store.send(.pageRequested(.accessibility, .request))
    #expect(store.state.mode == "single")
    await change(store) { $0[.accessibility] = .granted }
    #expect(store.state.presentation == .single(.init(permission: .accessibility, kind: .request, isClosing: true)))
    await clock.advance(by: .milliseconds(1_500))
    await store.receive(\.singleCloseElapsed)
    #expect(store.state.presentation == .hidden)
    #expect(windowCalls.value.last == "hide+front")
  }

  @Test
  func aGrantThatWaitsForARelaunchOffersRestartAndReopensThePageOnceAfterIt() async {
    let store = makeStore(progress: .finished)
    await store.send(.pageRequested(.screenRecording, .request))
    await change(store) { $0[.screenRecording] = .grantedAfterRestart }
    // ✓ with "Restart Vortex" and "Later": no auto-close.
    #expect(store.state.presentation == .single(.init(permission: .screenRecording, kind: .request)))
    await store.send(.restartTapped)
    await store.finish(timeout: .seconds(1))
    #expect(relaunches.value == 1)
    #expect(saved.value.last?.pendingSingle == .screenRecording)

    let relaunched = makeStore(progress: saved.value.last!, statuses: [.screenRecording: .granted])
    await relaunched.send(.launched)
    #expect(relaunched.state.presentation == .single(.init(permission: .screenRecording, kind: .afterRelaunch, isClosing: true)))
    #expect(relaunched.state.progress.pendingSingle == nil)
    await clock.advance(by: .milliseconds(1_500))
    await relaunched.receive(\.singleCloseElapsed)
    #expect(relaunched.state.presentation == .hidden)

    // Still off after the relaunch: the page stays, with its checkbox off.
    var pending = OnboardingProgress.finished
    pending.pendingSingle = .pasteboard
    let stillOff = makeStore(progress: pending)
    await stillOff.send(.launched)
    #expect(stillOff.state.presentation == .single(.init(permission: .pasteboard, kind: .afterRelaunch)))
  }

  @Test
  func laterAndEscapeAndCloseHideASinglePageAndGiveTheFrontBack() async {
    let store = makeStore(progress: .finished)
    await store.send(.pageRequested(.accessibility, .request))
    await store.send(.escapePressed)
    #expect(store.state.presentation == .hidden)
    await store.send(.pageRequested(.accessibility, .request))
    await store.send(.closeTapped)
    #expect(store.state.presentation == .hidden)
    // Esc does nothing in the onboarding itself (S79).
    let flow = makeStore()
    await flow.send(.launched)
    await flow.send(.escapePressed)
    #expect(flow.state.presentation == .flow)
    await effectsRun()
    #expect(windowCalls.value.filter { $0.hasPrefix("hide") } == ["hide+front", "hide+front"])
  }

  @Test
  func aNewRequestSwitchesTheSinglePageAndClosesThePanelOfTheOldOne() async {
    let store = makeStore(progress: .finished)
    await store.send(.pageRequested(.accessibility, .request))
    await store.send(.turnOnTapped(.accessibility))
    await store.send(.appActivated(OnboardingFeature.systemSettingsID))
    #expect(store.state.isPanel)
    await store.send(.pageRequested(.screenRecording, .request))
    #expect(store.state.presentation == .single(.init(permission: .screenRecording, kind: .request)))
    #expect(!store.state.isPanel)
  }

  @Test
  func aPageTheRefusedLockOpenedSaysToFlipTheSwitchAndNeverClosesByItself() async {
    let store = makeStore(progress: .finished, statuses: [.accessibility: .granted])
    await store.send(.pageRequested(.accessibility, .lockRefused))
    #expect(store.state.showsRecheckHint(.accessibility))
    await change(store) { $0[.notifications] = .granted }
    #expect(store.state.presentation == .single(.init(permission: .accessibility, kind: .lockRefused)))
    await store.send(.openPaneTapped(.accessibility))
    await clock.advance(by: .milliseconds(10))
    #expect(mac.state.events.last == .settings(.accessibility))
  }

  // MARK: - Blocked (S9, S41, S46, S65)

  @Test
  func blockedAfterCompletionShowsTheFirstMissingRequiredPageWithCloseOnly() async {
    let store = makeStore(progress: .finished, required: [.accessibility, .screenRecording])
    await store.send(.launched)
    #expect(store.state.presentation == .single(.init(permission: .accessibility, kind: .blocked)))
    #expect(store.state.mode == "blocked")
    #expect(store.state.progress.completed)
    await store.send(.closeTapped)
    #expect(store.state.presentation == .hidden)
    // A hover shows it again without activating; a click activates (S46).
    await store.send(.blockedEntry(activate: false))
    await store.send(.blockedEntry(activate: false))
    await store.send(.blockedEntry(activate: true))
    await effectsRun()
    #expect(windowCalls.value == ["window+activate", "hide+front", "window", "window+activate"])

    // The grant: ✓, then the next missing required page; then close.
    await change(store) { $0[.accessibility] = .granted }
    await clock.advance(by: .milliseconds(1_500))
    await store.receive(\.singleCloseElapsed)
    #expect(store.state.presentation == .single(.init(permission: .screenRecording, kind: .blocked)))
    await change(store) { $0[.screenRecording] = .grantedAfterRestart }
    await clock.advance(by: .milliseconds(1_500))
    await store.receive(\.singleCloseElapsed)
    #expect(store.state.presentation == .hidden)
  }

  @Test
  func whileBlockedEveryRequestShowsTheBlockingPage() async {
    let store = makeStore(progress: .finished, required: [.accessibility])
    await store.send(.pageRequested(.screenRecording, .request))
    #expect(store.state.presentation == .single(.init(permission: .accessibility, kind: .blocked)))
  }

  @Test
  func blockedBeforeCompletionJumpsToTheFirstPageWithAMissingRequiredPermission() async {
    let store = makeStore(progress: .at(.welcome), required: [.screenRecording])
    await store.send(.launched)
    #expect(store.state.presentation == .flow)
    #expect(store.state.page == .permission(.screenRecording))
    #expect(store.state.mode == "blocked")
    // After the grant, Next continues the normal flow.
    await settle(store)
    write([.screenRecording: .granted])
    await go(store, .nextTapped)
    #expect(store.state.page == .permission(.pasteboard))
  }

  // MARK: - The guide panel (S15, S59, S63, S73)

  @Test
  func systemSettingsInFrontSoonAfterTurnOnShrinksTheWindowToThePanel() async {
    let store = makeStore(progress: .at(.permission(.accessibility)))
    await store.send(.launched)
    await store.send(.turnOnTapped(.accessibility))
    await store.send(.appActivated(OnboardingFeature.systemSettingsID))
    #expect(store.state.isPanel)
    #expect(store.state.guided == .accessibility)
    #expect(store.state.mode == "guide")
    // Another app in front hides it; System Settings or Vortex brings it back (S63).
    await store.send(.appActivated("com.apple.finder"))
    #expect(store.state.isPanelHidden)
    await store.send(.appActivated("vortex"))
    #expect(!store.state.isPanelHidden)
    // The grant turns it back into the window, in front.
    await change(store) { $0[.accessibility] = .granted }
    #expect(!store.state.isPanel)
    await effectsRun()
    #expect(windowCalls.value == ["window+activate", "panel", "panelHidden", "panel", "window+activate"])
  }

  @Test
  func thePanelTurnsBackOnBackOrWhenSystemSettingsQuitsAndThePageThenSaysToFlipTheSwitch() async {
    let store = makeStore(progress: .at(.permission(.screenRecording)))
    await store.send(.launched)
    await store.send(.turnOnTapped(.screenRecording))
    await store.send(.appActivated(OnboardingFeature.systemSettingsID))
    await store.send(.backTapped)
    #expect(!store.state.isPanel)
    // Back cancels shrinking until the next request (S73).
    await store.send(.appActivated(OnboardingFeature.systemSettingsID))
    #expect(!store.state.isPanel)
    // Still off on return: "Already on in System Settings? Turn it off and on again." (S59).
    #expect(store.state.showsRecheckHint(.screenRecording))

    await store.send(.turnOnUnlocked(.screenRecording))
    await store.send(.turnOnTapped(.screenRecording))
    await store.send(.appActivated(OnboardingFeature.systemSettingsID))
    #expect(store.state.isPanel)
    await store.send(.appTerminated(OnboardingFeature.systemSettingsID))
    #expect(!store.state.isPanel)
  }

  @Test
  func systemSettingsLaterThanTenSecondsAfterTheRequestLeavesTheWindowAsItIs() async {
    let store = makeStore(progress: .at(.permission(.accessibility)))
    await store.send(.launched)
    await store.send(.turnOnTapped(.accessibility))
    await clock.advance(by: .seconds(10))
    await store.receive(\.guideExpired)
    await store.send(.appActivated(OnboardingFeature.systemSettingsID))
    #expect(!store.state.isPanel)
  }

  // MARK: - Open at login (S13, S74, S81)

  @Test
  func inReleaseBuildsOpenAtLoginIsAChoiceAppliedWhenLeavingBasics() async {
    let store = makeStore(progress: .at(.basics), appliesLoginItem: true)
    await store.send(.launched)
    #expect(store.state.openAtLoginChoice)
    // Nothing registers while Basics shows.
    #expect(loginItem.value.isEmpty)
    await store.send(.skipTapped)
    await effectsRun()
    await clock.advance(by: .milliseconds(10))
    #expect(loginItem.value == ["firstLaunch"])
    #expect(saved.value.last?.loginItemApplied == true)

    // Turned off on Basics: nothing registers.
    loginItem.setValue([])
    let off = makeStore(progress: .at(.basics), appliesLoginItem: true)
    await off.send(.launched)
    await off.send(.loginItemToggled(false))
    #expect(!off.state.openAtLoginChoice)
    await off.send(.skipTapped)
    await clock.advance(by: .milliseconds(10))
    #expect(loginItem.value.isEmpty)
  }

  @Test
  func debugBuildsNeverRegisterByThemselvesAndTheSwitchActsAtOnce() async {
    let store = makeStore(progress: .at(.basics), appliesLoginItem: false)
    await store.send(.launched)
    await store.send(.skipTapped)
    await clock.advance(by: .milliseconds(10))
    #expect(loginItem.value.isEmpty)
    await go(store, .doneRowTapped(.notifications))
    await store.send(.loginItemToggled(true))
    await store.receive(\.loginItemStatusLoaded) { $0.loginItem = .enabled }
    #expect(loginItem.value == ["set:true"])
  }

  @Test
  func basicsReReadsTheLoginItemEverySecondWhileItShows() async {
    let reads = LockIsolated(0)
    let store = makeStore(progress: .at(.basics))
    store.dependencies.launchAtLoginClient.status = { reads.withValue { $0 += 1 }; return .requiresApproval }
    await store.send(.launched)
    await clock.advance(by: .seconds(2))
    await effectsRun()
    #expect(reads.value >= 3)
    await store.send(.closeTapped)
    let afterClose = reads.value
    await clock.advance(by: .seconds(3))
    #expect(reads.value == afterClose)
  }

  // MARK: - QA

  @Test
  func resetStartsTheOnboardingOver() async {
    let store = makeStore(progress: .finished)
    await store.send(.reset)
    #expect(store.state.progress == OnboardingProgress())
    #expect(saved.value.last == OnboardingProgress())
  }

  @Test
  func progressReadsFilesFromOtherBuildsAndRoundTrips() throws {
    let old = try JSONDecoder().decode(OnboardingProgress.self, from: Data(#"{"page":"basics"}"#.utf8))
    #expect(old.page == "basics")
    #expect(!old.completed)
    var progress = OnboardingProgress.at(.step("secrets"))
    progress.pendingChecks = [.pasteboard]
    progress.pendingSingle = .accessibility
    let data = try JSONEncoder().encode(progress)
    #expect(try JSONDecoder().decode(OnboardingProgress.self, from: data) == progress)
    for page: OnboardingPage in [.welcome, .basics, .permission(.screenRecording), .step("secrets"), .done] {
      #expect(OnboardingPage(id: page.id) == page)
    }
  }
}
