import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import VortexShell

@MainActor
struct OnboardingFeatureTests {
  let clock = TestClock()
  let saved = LockIsolated<[OnboardingProgress]>([])
  /// "window", "window+activate", "panel", "panelHidden", "hide", "hide+front".
  let windowCalls = CallLog()
  /// "on" and "off" for the 1 s checks.
  let checks = CallLog()
  let relaunches = CallLog()
  /// "request:<permission>" and "pane:<permission>", after the simulated macOS took them.
  let asked = CallLog()
  /// "register", "unregister", "firstLaunch:registered", "firstLaunch:kept", "status".
  let loginItem = CallLog()
  let loginStatus = LockIsolated<LaunchAtLoginStatus>(.disabled)
  /// The login item was set up before, by an earlier release build.
  let loginSetUp = LockIsolated(false)
  let shortcut = LockIsolated<String?>(nil)
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
    state.stepOrder = steps
    state.ownBundleID = "vortex"
    state.appliesLoginItem = appliesLoginItem
    let simulated = PermissionsClient.simulated(mac)
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.onboardingProgress.save = { [saved] progress in saved.withValue { $0.append(progress) } }
      $0.onboardingWindow.present = { [windowCalls] mode, activate in
        windowCalls.record(mode.rawValue + (activate ? "+activate" : ""))
      }
      $0.onboardingWindow.hide = { [windowCalls] restoreFront in
        windowCalls.record(restoreFront ? "hide+front" : "hide")
      }
      $0.permissionsClient = simulated
      $0.permissionsClient.request = { [asked] permission in
        await simulated.request(permission)
        asked.record("request:\(permission)")
      }
      $0.permissionsClient.openSettings = { [asked] permission in
        await simulated.openSettings(permission)
        asked.record("pane:\(permission)")
      }
      $0.permissionsClient.setFrequentChecks = { [checks] isOn in checks.record(isOn ? "on" : "off") }
      $0.systemClient.relaunch = { [relaunches] in relaunches.record("relaunch") }
      $0.hotkeyClient.shortcut = { [shortcut] _ in shortcut.value }
      // As the live login item does: the first-launch setup registers only if nothing was set up before.
      $0.launchAtLoginClient.status = { [loginItem, loginStatus] in
        loginItem.record("status")
        return loginStatus.value
      }
      $0.launchAtLoginClient.isSetUp = { [loginSetUp] in loginSetUp.value }
      $0.launchAtLoginClient.setEnabled = { [loginItem, loginStatus] isOn in
        loginItem.record(isOn ? "register" : "unregister")
        loginStatus.setValue(isOn ? .enabled : .disabled)
        return loginStatus.value
      }
      $0.launchAtLoginClient.enableOnFirstLaunch = { [loginItem, loginStatus, loginSetUp] in
        guard !loginSetUp.value else { return loginItem.record("firstLaunch:kept") }
        loginSetUp.setValue(true)
        loginStatus.setValue(.enabled)
        loginItem.record("firstLaunch:registered")
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

  func go(_ store: TestStoreOf<OnboardingFeature>, _ action: OnboardingFeature.Action) async {
    await store.send(action)
    await settle(store)
  }

  /// The login item calls up to the one expected, skipping the status reads Basics makes every second.
  func nextLoginChange() async -> String? {
    while let call = await loginItem.next() {
      if call != "status" { return call }
    }
    return nil
  }

  /// The guide panel up for `permission`: Turn on, then System Settings in front.
  func openPanel(_ store: TestStoreOf<OnboardingFeature>, for permission: Permission) async {
    await store.send(.turnOnTapped(permission))
    await store.send(.appActivated(OnboardingFeature.systemSettingsID))
    #expect(await windowCalls.next() == "panel")
  }

  // MARK: - When the window shows (S7, S8, S21, S71)

  @Test
  func aFreshInstallShowsWelcomeAtLaunchAndChecksEverySecondWhileItShows() async {
    let store = makeStore()
    await store.send(.launched)
    #expect(store.state.presentation == .flow(.window))
    #expect(store.state.page == .welcome)
    #expect(await windowCalls.next() == "window+activate")
    #expect(await checks.next() == "on")
  }

  @Test
  func aCompletedOnboardingShowsNothingAtLaunch() async {
    let store = makeStore(progress: .finished)
    await store.send(.launched)
    #expect(store.state.presentation == .hidden)
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
    #expect(next.state.presentation == .flow(.window))
  }

  @Test
  func aSavedPageThatNoLongerExistsResumesAtTheNextPageInOrder() {
    // Tasks was turned off, so there is no Screen Recording page any more.
    let store = makeStore(
      progress: .at(.permission(.screenRecording)),
      features: [OnboardingNeeds.home, OnboardingNeeds.timer, OnboardingNeeds.clipboard]
    )
    #expect(store.state.page == .permission(.pasteboard))
    let noneLeft = makeStore(progress: .at(.permission(.screenRecording)), features: [OnboardingNeeds.home])
    #expect(noneLeft.state.page == .done)
  }

  /// Steps sit in the order of their features in the sidebar: a step whose feature was turned off resumes at the next
  /// step, not at Done (S71).
  @Test
  func aSavedStepWhoseFeatureIsOffResumesAtTheNextStep() {
    var state = makeStore(progress: .at(.step("secrets")), steps: ["tasks"]).state
    state.stepOrder = ["secrets", "tasks"]
    #expect(state.page == .step("tasks"))
    state.stepOrder = ["tasks", "secrets"]
    #expect(state.page == .done)
  }

  @Test
  func aPageIdThisBuildCanNotReadStartsAtWelcome() {
    var progress = OnboardingProgress()
    progress.page = "nonsense"
    #expect(makeStore(progress: progress).state.page == .welcome)
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
  func skipAndNextFollowTheStatusesOnThePage() {
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
  func aGrantThatWaitsForARelaunchCountsAsOnAndOffersRestartNow() async {
    let store = makeStore(progress: .at(.permission(.screenRecording)), statuses: [.screenRecording: .grantedAfterRestart])
    await store.send(.launched)
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

  // MARK: - Turn on (S2, S4, S13, S70)

  @Test
  func turnOnAsksMacOSOnceUntilTheStatusChangesOrTwoSecondsPass() async {
    let store = makeStore(progress: .at(.permission(.accessibility)))
    await store.send(.launched)
    await store.send(.turnOnTapped(.accessibility))
    await store.send(.turnOnTapped(.accessibility))
    #expect(await asked.next() == "request:accessibility")
    #expect(mac.state.events == [.prompt(.accessibility)])
    await clock.advance(by: .seconds(2))
    await store.receive(\.turnOnUnlocked)
    #expect(!store.state.turnOnIgnored.contains(.accessibility))
    // A click on a checkbox that is on does nothing (S2).
    write([.accessibility: .granted])
    await store.send(.turnOnTapped(.accessibility))
    #expect(!store.state.turnOnIgnored.contains(.accessibility))
    #expect(asked.untaken.isEmpty)
  }

  /// The pasteboard's ↻ checkbox reads as on while its check waits for the relaunch: a click asks nothing (S2).
  @Test
  func thePasteboardsCheckboxThatWaitsForTheRelaunchDoesNothing() async {
    let store = makeStore(progress: .at(.permission(.pasteboard)))
    await store.send(.launched)
    await store.send(.turnOnTapped(.pasteboard))
    #expect(await asked.next() == "request:pasteboard")
    await clock.advance(by: .seconds(2))
    await store.receive(\.turnOnUnlocked)
    #expect(store.state.rowState(.pasteboard) == .afterRestart)
    await store.send(.turnOnTapped(.pasteboard))
    #expect(!store.state.turnOnIgnored.contains(.pasteboard))
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
    #expect(store.state.showsRestartToCheck(.pasteboard))
  }

  @Test
  func restartAndStartRelaunchesOnceThenDoneShowsRealStatesAndStarts() async {
    let store = makeStore(progress: .at(.done), statuses: [
      .notifications: .granted, .accessibility: .granted, .screenRecording: .grantedAfterRestart, .pasteboard: .notNeeded,
    ])
    await store.send(.launched)
    #expect(store.state.finishRestarts)
    await store.send(.finishTapped)
    #expect(await relaunches.next() == "relaunch")
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
    #expect(relaunches.untaken.isEmpty)
  }

  /// A second press before the process is gone neither completes the onboarding nor relaunches again (S18, S70).
  @Test
  func aSecondPressOfRestartAndStartDoesNothing() async {
    let store = makeStore(progress: .at(.done), statuses: [
      .notifications: .granted, .accessibility: .granted, .screenRecording: .grantedAfterRestart, .pasteboard: .notNeeded,
    ])
    await store.send(.launched)
    await store.send(.finishTapped)
    #expect(store.state.isRelaunching)
    await store.send(.finishTapped)
    await store.send(.doneRowTapped(.screenRecording))
    #expect(!store.state.progress.completed)
    #expect(store.state.page == .done)
    #expect(saved.value.last?.completed == false)
    #expect(await relaunches.next() == "relaunch")
    #expect(relaunches.untaken.isEmpty)
  }

  @Test
  func restartNowKeepsThePageTakesOnePressAndQuitAndReopenResumesThere() async {
    let store = makeStore(progress: .at(.permission(.screenRecording)), statuses: [.screenRecording: .grantedAfterRestart])
    await store.send(.launched)
    await store.send(.restartTapped)
    await store.send(.restartTapped)
    await store.send(.nextTapped)
    #expect(await relaunches.next() == "relaunch")
    #expect(saved.value.last?.page == "permission:screenRecording")
    #expect(saved.value.last?.restarted == true)
    #expect(relaunches.untaken.isEmpty)

    // System Settings' own Quit & Reopen: Vortex starts again at the same page, with fresh statuses.
    var reopened = OnboardingProgress.at(.permission(.pasteboard))
    reopened.pendingChecks = [.pasteboard]
    let store2 = makeStore(progress: reopened, statuses: [.pasteboard: .granted])
    await store2.send(.launched)
    #expect(store2.state.page == .permission(.pasteboard))
    #expect(store2.state.rowState(.pasteboard) == .on)
    #expect(store2.state.progress.restarted)
  }

  /// Nothing relaunches from a page that shows no restart link.
  @Test
  func restartDoesNothingWhereNoRestartShows() async {
    let store = makeStore(progress: .at(.permission(.accessibility)))
    await store.send(.launched)
    await store.send(.restartTapped)
    #expect(!store.state.isRelaunching)
    #expect(!store.state.progress.restarted)
  }

  // MARK: - Done (S18, S53, S75, S77)

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

  @Test
  func donesHintNamesWhatOpensVortexHere() {
    var state = makeStore().state
    state.doneHint = .init(notch: .hover, menuBarIcon: true)
    #expect(state.doneHintText == .hoverOrIcon)
    state.doneHint = .init(notch: .hover, menuBarIcon: false)
    #expect(state.doneHintText == .hover)
    state.openShortcut = "⌥⌘V"
    #expect(state.doneHintText == .hoverOrShortcut("⌥⌘V"))
    // With the icon showing, the icon is named, not the shortcut.
    state.doneHint = .init(notch: .click, menuBarIcon: true)
    #expect(state.doneHintText == .clickOrIcon)
    state.doneHint = .init(notch: .click, menuBarIcon: false)
    #expect(state.doneHintText == .clickOrShortcut("⌥⌘V"))
    state.openShortcut = nil
    #expect(state.doneHintText == .click)
    // A Mac without a notch gets only the menu bar part.
    state.doneHint = .init(notch: nil, menuBarIcon: true)
    #expect(state.doneHintText == .icon)
  }

  @Test
  func doneReadsTheOpenVortexShortcutWhenItShows() async {
    shortcut.setValue("⌥⌘V")
    let store = makeStore(progress: .at(.done))
    await store.send(.launched)
    await store.receive(\.openShortcutLoaded) { $0.openShortcut = "⌥⌘V" }
  }

  // MARK: - Closing and continuing (S10, S69, S80)

  @Test
  func closingBeforeCompletionKeepsTheProgressAndContinueSetupReopensAtTheSavedPage() async {
    let store = makeStore(progress: .at(.permission(.accessibility)))
    await store.send(.launched)
    #expect(await windowCalls.next() == "window+activate")
    await store.send(.closeTapped)
    #expect(await windowCalls.next() == "hide")
    #expect(store.state.presentation == .hidden)
    #expect(store.state.progress.page == "permission:accessibility")
    #expect(!store.state.progress.completed)
    // A request now shows a single page, and the saved page stays (S52).
    await store.send(.pageRequested(.screenRecording, .request))
    #expect(await windowCalls.next() == "window+activate")
    #expect(store.state.presentation == .single(.init(permission: .screenRecording, kind: .request), .window))
    // «Продовжити налаштування» replaces it with the onboarding at the saved page (S80).
    await store.send(.continueSetupTapped)
    #expect(await windowCalls.next() == "window+activate")
    #expect(store.state.presentation == .flow(.window))
    #expect(store.state.page == .permission(.accessibility))
  }

  // MARK: - The panel stepped aside, and the onboarding brought forward (S9, S52, S63, S69)

  /// «Продовжити налаштування» while another app is in front and the panel stepped aside: the window comes back, in
  /// front, as the System Settings window the panel stood next to is behind that app.
  @Test
  func continueSetupWhileThePanelSteppedAsideBringsTheWindowBack() async {
    let store = makeStore(progress: .at(.permission(.accessibility)))
    await store.send(.launched)
    #expect(await windowCalls.next() == "window+activate")
    await openPanel(store, for: .accessibility)
    await store.send(.appActivated("com.apple.Safari"))
    #expect(await windowCalls.next() == "panelHidden")
    await store.send(.continueSetupTapped)
    #expect(await windowCalls.next() == "window+activate")
    #expect(store.state.presentation == .flow(.window))
  }

  @Test
  func whileThePanelShowsContinueSetupAndARequestBringItForwardAsAPanel() async {
    let store = makeStore(progress: .at(.permission(.accessibility)))
    await store.send(.launched)
    #expect(await windowCalls.next() == "window+activate")
    await openPanel(store, for: .accessibility)
    await store.send(.continueSetupTapped)
    #expect(await windowCalls.next() == "panel+activate")
    await store.send(.pageRequested(.screenRecording, .request))
    #expect(await windowCalls.next() == "panel+activate")
    #expect(store.state.presentation == .flow(.panel(.accessibility, isHidden: false)))
    // Stepped aside, a request brings the window back.
    await store.send(.appActivated("com.apple.Safari"))
    #expect(await windowCalls.next() == "panelHidden")
    await store.send(.pageRequested(.screenRecording, .request))
    #expect(await windowCalls.next() == "window+activate")
  }

  @Test
  func whileBlockedAClickOrAHoverBringsTheWindowBackWhenThePanelSteppedAside() async {
    let store = makeStore(progress: .at(.permission(.accessibility)), required: [.accessibility])
    await store.send(.launched)
    #expect(await windowCalls.next() == "window+activate")
    await openPanel(store, for: .accessibility)
    await store.send(.appActivated("com.apple.Safari"))
    #expect(await windowCalls.next() == "panelHidden")
    // A hover shows the window without activating Vortex (S46).
    await store.send(.blockedEntry(activate: false))
    #expect(await windowCalls.next() == "window")
    #expect(store.state.presentation == .flow(.window))
    // Showing already: a hover does nothing, a click activates.
    await store.send(.blockedEntry(activate: false))
    await store.send(.blockedEntry(activate: true))
    #expect(await windowCalls.next() == "window+activate")

    // The same for a click while the panel stepped aside.
    await store.send(.turnOnUnlocked(.accessibility))
    await openPanel(store, for: .accessibility)
    await store.send(.appActivated("com.apple.Safari"))
    #expect(await windowCalls.next() == "panelHidden")
    await store.send(.blockedEntry(activate: true))
    #expect(await windowCalls.next() == "window+activate")
  }

  // MARK: - The single page (S11, S24, S49–S52, S55)

  @Test
  func aRequestWhileTheOnboardingShowsBringsItForwardWithoutJumping() async {
    let store = makeStore(progress: .at(.basics))
    await store.send(.launched)
    #expect(await windowCalls.next() == "window+activate")
    await store.send(.pageRequested(.screenRecording, .request))
    #expect(await windowCalls.next() == "window+activate")
    #expect(store.state.presentation == .flow(.window))
    #expect(store.state.page == .basics)
  }

  @Test
  func aSinglePageClosesSecondsAfterTheGrant() async {
    let store = makeStore(progress: .finished)
    await store.send(.pageRequested(.accessibility, .request))
    #expect(await windowCalls.next() == "window+activate")
    #expect(store.state.mode == "single")
    await change(store) { $0[.accessibility] = .granted }
    #expect(store.state.presentation == .single(.init(permission: .accessibility, kind: .request, isClosing: true), .window))
    await clock.advance(by: .milliseconds(1_500))
    await store.receive(\.singleCloseElapsed)
    #expect(store.state.presentation == .hidden)
    #expect(await windowCalls.next() == "hide+front")
  }

  /// A pasteboard grant reads `notNeeded` (report-1, concern 1): the page closes on it as on `granted` (S50).
  @Test
  func thePasteboardsSinglePageClosesOnceItReadsNotNeeded() async {
    var pending = OnboardingProgress.finished
    pending.pendingSingle = .pasteboard
    let store = makeStore(progress: pending, statuses: [.pasteboard: .notNeeded])
    await store.send(.launched)
    #expect(store.state.presentation == .single(.init(permission: .pasteboard, kind: .afterRelaunch, isClosing: true), .window))
    await clock.advance(by: .milliseconds(1_500))
    await store.receive(\.singleCloseElapsed)
    #expect(store.state.presentation == .hidden)

    let live = makeStore(progress: .finished, statuses: [.pasteboard: .notGranted])
    await live.send(.pageRequested(.pasteboard, .request))
    await change(live) { $0[.pasteboard] = .notNeeded }
    #expect(live.state.single?.isClosing == true)
  }

  @Test
  func aGrantThatWaitsForARelaunchOffersRestartAndReopensThePageOnceAfterIt() async {
    let store = makeStore(progress: .finished)
    await store.send(.pageRequested(.screenRecording, .request))
    await change(store) { $0[.screenRecording] = .grantedAfterRestart }
    // ✓ with "Restart Vortex" and "Later": no auto-close.
    #expect(store.state.presentation == .single(.init(permission: .screenRecording, kind: .request), .window))
    #expect(store.state.waitsForRelaunch)
    await store.send(.restartTapped)
    #expect(await relaunches.next() == "relaunch")
    #expect(saved.value.last?.pendingSingle == .screenRecording)

    let relaunched = makeStore(progress: saved.value.last!, statuses: [.screenRecording: .granted])
    await relaunched.send(.launched)
    #expect(relaunched.state.presentation == .single(.init(permission: .screenRecording, kind: .afterRelaunch, isClosing: true), .window))
    #expect(relaunched.state.progress.pendingSingle == nil)
    await clock.advance(by: .milliseconds(1_500))
    await relaunched.receive(\.singleCloseElapsed)
    #expect(relaunched.state.presentation == .hidden)

    // Still off after the relaunch: the page stays, with its checkbox off.
    var pending = OnboardingProgress.finished
    pending.pendingSingle = .accessibility
    let stillOff = makeStore(progress: pending)
    await stillOff.send(.launched)
    #expect(stillOff.state.presentation == .single(.init(permission: .accessibility, kind: .afterRelaunch), .window))
  }

  /// Blocked at launch, the blocking page opens even though a page waits for this relaunch (S41).
  @Test
  func aPageWaitingForTheRelaunchGivesWayToTheBlockingPage() async {
    var pending = OnboardingProgress.finished
    pending.pendingSingle = .screenRecording
    let store = makeStore(progress: pending, required: [.accessibility], statuses: [
      .notifications: .granted, .accessibility: .notGranted, .screenRecording: .granted, .pasteboard: .notNeeded,
    ])
    await store.send(.launched)
    #expect(store.state.presentation == .single(.init(permission: .accessibility, kind: .blocked), .window))
    #expect(store.state.progress.pendingSingle == nil)
  }

  @Test
  func escapeCloseAndLaterHideASinglePageAndGiveTheFrontBack() async {
    let store = makeStore(progress: .finished)
    await store.send(.pageRequested(.accessibility, .request))
    #expect(await windowCalls.next() == "window+activate")
    await store.send(.escapePressed)
    #expect(await windowCalls.next() == "hide+front")
    #expect(store.state.presentation == .hidden)
    await store.send(.pageRequested(.accessibility, .request))
    #expect(await windowCalls.next() == "window+activate")
    // "Later" shows only while the grant waits for a relaunch.
    await store.send(.laterTapped)
    #expect(store.state.isVisible)
    await store.send(.closeTapped)
    #expect(await windowCalls.next() == "hide+front")
    await store.send(.pageRequested(.screenRecording, .request))
    #expect(await windowCalls.next() == "window+activate")
    await change(store) { $0[.screenRecording] = .grantedAfterRestart }
    await store.send(.laterTapped)
    #expect(await windowCalls.next() == "hide+front")

    // Esc does nothing in the onboarding itself (S79).
    let flow = makeStore()
    await flow.send(.launched)
    await flow.send(.escapePressed)
    #expect(flow.state.presentation == .flow(.window))
  }

  @Test
  func aNewRequestSwitchesTheSinglePageAndClosesThePanelOfTheOldOne() async {
    let store = makeStore(progress: .finished)
    await store.send(.pageRequested(.accessibility, .request))
    #expect(await windowCalls.next() == "window+activate")
    await openPanel(store, for: .accessibility)
    #expect(store.state.isPanel)
    await store.send(.pageRequested(.screenRecording, .request))
    #expect(await windowCalls.next() == "window+activate")
    #expect(store.state.presentation == .single(.init(permission: .screenRecording, kind: .request), .window))
    #expect(!store.state.isPanel)
  }

  @Test
  func aPageTheRefusedLockOpenedSaysToFlipTheSwitchAndNeverClosesByItself() async {
    let store = makeStore(progress: .finished, statuses: [.accessibility: .granted])
    await store.send(.pageRequested(.accessibility, .lockRefused))
    #expect(store.state.showsRecheckHint(.accessibility))
    await change(store) { $0[.notifications] = .granted }
    #expect(store.state.presentation == .single(.init(permission: .accessibility, kind: .lockRefused), .window))
    await store.send(.openPaneTapped(.accessibility))
    #expect(await asked.next() == "pane:accessibility")
    #expect(mac.state.events.last == .settings(.accessibility))
  }

  // MARK: - Blocked (S9, S41, S46, S65)

  @Test
  func blockedAfterCompletionShowsTheFirstMissingRequiredPageWithCloseOnly() async {
    let store = makeStore(progress: .finished, required: [.accessibility, .screenRecording])
    await store.send(.launched)
    #expect(await windowCalls.next() == "window+activate")
    #expect(store.state.presentation == .single(.init(permission: .accessibility, kind: .blocked), .window))
    #expect(store.state.mode == "blocked")
    #expect(store.state.progress.completed)
    await store.send(.closeTapped)
    #expect(await windowCalls.next() == "hide+front")
    #expect(store.state.presentation == .hidden)
    // A hover shows it again without activating; another hover leaves it; a click activates (S46).
    await store.send(.blockedEntry(activate: false))
    #expect(await windowCalls.next() == "window")
    await store.send(.blockedEntry(activate: false))
    await store.send(.blockedEntry(activate: true))
    #expect(await windowCalls.next() == "window+activate")

    // The grant: ✓, then the next missing required page; then close.
    await change(store) { $0[.accessibility] = .granted }
    await clock.advance(by: .milliseconds(1_500))
    await store.receive(\.singleCloseElapsed)
    #expect(store.state.presentation == .single(.init(permission: .screenRecording, kind: .blocked), .window))
    await change(store) { $0[.screenRecording] = .grantedAfterRestart }
    await clock.advance(by: .milliseconds(1_500))
    await store.receive(\.singleCloseElapsed)
    #expect(store.state.presentation == .hidden)
  }

  @Test
  func whileBlockedEveryRequestShowsTheBlockingPage() async {
    let store = makeStore(progress: .finished, required: [.accessibility])
    await store.send(.pageRequested(.screenRecording, .request))
    #expect(store.state.presentation == .single(.init(permission: .accessibility, kind: .blocked), .window))
  }

  @Test
  func blockedBeforeCompletionJumpsToTheFirstPageWithAMissingRequiredPermission() async {
    let store = makeStore(progress: .at(.welcome), required: [.screenRecording])
    await store.send(.launched)
    #expect(store.state.presentation == .flow(.window))
    #expect(store.state.page == .permission(.screenRecording))
    #expect(store.state.mode == "blocked")
    // After the grant, Next continues the normal flow.
    await settle(store)
    write([.screenRecording: .granted])
    await go(store, .nextTapped)
    #expect(store.state.page == .permission(.pasteboard))
  }

  /// «Продовжити налаштування» while blocked before completion shows the page of the missing permission (S65).
  @Test
  func continueSetupWhileBlockedShowsThePageOfTheMissingPermission() async {
    let store = makeStore(progress: .at(.basics), required: [.accessibility])
    await store.send(.continueSetupTapped)
    #expect(store.state.presentation == .flow(.window))
    #expect(store.state.page == .permission(.accessibility))
  }

  // MARK: - The guide panel (S15, S59, S63, S73)

  @Test
  func systemSettingsInFrontSoonAfterTurnOnShrinksTheWindowToThePanel() async {
    let store = makeStore(progress: .at(.permission(.accessibility)))
    await store.send(.launched)
    #expect(await windowCalls.next() == "window+activate")
    await openPanel(store, for: .accessibility)
    #expect(store.state.guided == .accessibility)
    #expect(store.state.mode == "guide")
    // Another app in front hides it; System Settings or Vortex brings it back (S63).
    await store.send(.appActivated("com.apple.finder"))
    #expect(await windowCalls.next() == "panelHidden")
    #expect(store.state.isPanelHidden)
    await store.send(.appActivated("vortex"))
    #expect(await windowCalls.next() == "panel")
    #expect(!store.state.isPanelHidden)
    // The grant turns it back into the window, in front.
    await change(store) { $0[.accessibility] = .granted }
    #expect(await windowCalls.next() == "window+activate")
    #expect(!store.state.isPanel)
  }

  @Test
  func thePanelTurnsBackOnBackOrWhenSystemSettingsQuitsAndThePageThenSaysToFlipTheSwitch() async {
    let store = makeStore(progress: .at(.permission(.screenRecording)))
    await store.send(.launched)
    #expect(await windowCalls.next() == "window+activate")
    await openPanel(store, for: .screenRecording)
    await store.send(.backTapped)
    #expect(await windowCalls.next() == "window+activate")
    #expect(!store.state.isPanel)
    // Back cancels shrinking until the next request (S73).
    await store.send(.appActivated(OnboardingFeature.systemSettingsID))
    #expect(!store.state.isPanel)
    // Still off on return: "Already on in System Settings? Turn it off and on again." (S59).
    #expect(store.state.showsRecheckHint(.screenRecording))

    await store.send(.turnOnUnlocked(.screenRecording))
    await openPanel(store, for: .screenRecording)
    await store.send(.appTerminated(OnboardingFeature.systemSettingsID))
    #expect(await windowCalls.next() == "window+activate")
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
  func onAFreshInstallTheUntouchedSwitchShowsOnAndRegistersWhenLeavingBasics() async {
    let store = makeStore(progress: .at(.basics), appliesLoginItem: true)
    await store.send(.launched)
    await store.receive(\.loginItemSetUpLoaded)
    #expect(store.state.openAtLoginShown)
    // Nothing registers while Basics shows.
    await store.send(.skipTapped)
    #expect(await nextLoginChange() == "firstLaunch:registered")
    #expect(loginStatus.value == .enabled)
    #expect(saved.value.last?.loginItemApplied == true)
  }

  @Test
  func aFreshInstallThatTurnsTheSwitchOffKeepsItOff() async {
    let store = makeStore(progress: .at(.basics), appliesLoginItem: true)
    await store.send(.launched)
    await store.send(.loginItemToggled(false))
    #expect(!store.state.openAtLoginShown)
    await store.send(.skipTapped)
    #expect(await nextLoginChange() == "unregister")
    #expect(loginStatus.value == .disabled)
  }

  /// An install from before stage 7 registered at its first launch; the user turns it off on Basics (S13, S74).
  @Test
  func anExistingRegisteredLoginItemTurnedOffOnBasicsGoesOff() async {
    loginSetUp.setValue(true)
    loginStatus.setValue(.enabled)
    let store = makeStore(progress: .at(.basics), appliesLoginItem: true)
    await store.send(.launched)
    await store.receive(\.loginItemSetUpLoaded)
    await store.receive(\.loginItemStatusLoaded)
    #expect(store.state.openAtLoginShown)
    await store.send(.loginItemToggled(false))
    await store.send(.skipTapped)
    #expect(await nextLoginChange() == "unregister")
    #expect(loginStatus.value == .disabled)
  }

  /// An install that turned the login item off earlier shows it off, and turned on on Basics, it goes on (S74).
  @Test
  func anEarlierOffShowsOffAndTurnedOnOnBasicsGoesOn() async {
    loginSetUp.setValue(true)
    let store = makeStore(progress: .at(.basics), appliesLoginItem: true)
    await store.send(.launched)
    await store.receive(\.loginItemSetUpLoaded)
    await store.receive(\.loginItemStatusLoaded)
    #expect(!store.state.openAtLoginShown)
    await store.send(.loginItemToggled(true))
    await store.send(.skipTapped)
    #expect(await nextLoginChange() == "register")
    #expect(loginStatus.value == .enabled)

    // Untouched, it stays off.
    loginStatus.setValue(.disabled)
    let untouched = makeStore(progress: .at(.basics), appliesLoginItem: true)
    await untouched.send(.launched)
    await untouched.send(.skipTapped)
    #expect(await nextLoginChange() == "firstLaunch:kept")
    #expect(loginStatus.value == .disabled)
  }

  @Test
  func debugBuildsNeverRegisterByThemselvesAndTheSwitchActsAtOnce() async {
    let store = makeStore(progress: .at(.basics), appliesLoginItem: false)
    await store.send(.launched)
    #expect(!store.state.openAtLoginShown)
    await store.send(.loginItemToggled(true))
    #expect(await nextLoginChange() == "register")
    await store.receive(\.loginItemStatusLoaded, .enabled)
    #expect(store.state.openAtLoginShown)
    await store.send(.skipTapped)
    await settle(store)
    #expect(!loginItem.all.contains { $0.hasPrefix("firstLaunch") })
  }

  @Test
  func basicsReReadsTheLoginItemEverySecondWhileItShows() async {
    let store = makeStore(progress: .at(.basics))
    await store.send(.launched)
    #expect(await loginItem.next() == "status")
    await clock.advance(by: .seconds(2))
    #expect(await loginItem.next() == "status")
    #expect(await loginItem.next() == "status")
    await store.send(.closeTapped)
    #expect(await windowCalls.next() == "window+activate")
    #expect(await windowCalls.next() == "hide")
    await clock.advance(by: .seconds(3))
    #expect(loginItem.untaken.isEmpty)
  }

  // MARK: - QA and the saved progress (S71)

  @Test
  func resetStartsTheOnboardingOver() async {
    let store = makeStore(progress: .finished)
    await store.send(.reset)
    #expect(store.state.progress == OnboardingProgress())
    #expect(saved.value.last == OnboardingProgress())
  }

  @Test
  func progressRoundTripsAndPagesKeepTheirIds() throws {
    var progress = OnboardingProgress.at(.step("secrets"))
    progress.pendingChecks = [.pasteboard]
    progress.pendingSingle = .accessibility
    let data = try JSONEncoder().encode(progress)
    #expect(try JSONDecoder().decode(OnboardingProgress.self, from: data) == progress)
    for page: OnboardingPage in [.welcome, .basics, .permission(.screenRecording), .step("secrets"), .done] {
      #expect(OnboardingPage(id: page.id) == page)
    }
    #expect(OnboardingPage(id: "nonsense") == nil)
  }

  /// One unknown or broken value takes its default; `completed` and the rest stay (S71).
  @Test
  func progressReadsEachFieldOnItsOwn() throws {
    let old = try JSONDecoder().decode(OnboardingProgress.self, from: Data(#"{"page":"basics"}"#.utf8))
    #expect(old.page == "basics")
    #expect(!old.completed)
    let newer = try JSONDecoder().decode(OnboardingProgress.self, from: Data(#"""
      {"page": "done", "completed": true, "restarted": true, "pendingChecks": ["pasteboard", "camera"],
       "pendingSingle": "camera", "returnToDone": "yes", "loginItemApplied": 1, "future": {"a": 1}}
      """#.utf8))
    #expect(newer.completed)
    #expect(newer.restarted)
    #expect(newer.page == "done")
    #expect(newer.pendingChecks == [.pasteboard])
    #expect(newer.pendingSingle == nil)
    #expect(!newer.returnToDone)
    #expect(!newer.loginItemApplied)
  }

  @Test
  func theLiveProgressFileIsWrittenAtOnceAndReadBackLeniently() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "onboarding-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appending(path: "onboarding.json")
    let client = OnboardingProgressClient.live(at: url)
    // No file: a fresh onboarding.
    #expect(client.load() == OnboardingProgress())
    var progress = OnboardingProgress.at(.permission(.accessibility))
    progress.completed = true
    client.save(progress)
    // On disk as soon as `save` returns.
    #expect(FileManager.default.fileExists(atPath: url.path()))
    #expect(client.load() == progress)
    // A file that isn't JSON is a fresh onboarding; one with an unknown value keeps the rest.
    try Data("not json".utf8).write(to: url)
    #expect(client.load() == OnboardingProgress())
    try Data(#"{"completed": true, "pendingSingle": "camera"}"#.utf8).write(to: url)
    #expect(client.load().completed)
  }

  // MARK: - Where the panel goes (S15)

  @Test
  func thePanelGoesRightOfSystemSettingsThenLeftThenBottomRight() {
    let size = OnboardingWindowController.panelSize
    let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
    // Room on the right: right of it, its top edges aligned.
    let settings = CGRect(x: 200, y: 200, width: 700, height: 600)
    let right = OnboardingWindowController.panelFrame(next: settings, size: size, screens: [screen])
    #expect(right == CGRect(x: 912, y: 500, width: size.width, height: size.height))
    // No room on the right: left of it.
    let wide = CGRect(x: 400, y: 200, width: 900, height: 600)
    let left = OnboardingWindowController.panelFrame(next: wide, size: size, screens: [screen])
    #expect(left == CGRect(x: 48, y: 500, width: size.width, height: size.height))
    // No room on either side: bottom right of its display.
    let full = CGRect(x: 100, y: 100, width: 1_300, height: 700)
    let corner = OnboardingWindowController.panelFrame(next: full, size: size, screens: [screen])
    #expect(corner == CGRect(x: 1_080, y: 20, width: size.width, height: size.height))
    // No System Settings window listed yet: bottom right of the first display.
    #expect(OnboardingWindowController.panelFrame(next: nil, size: size, screens: [screen]) == corner)
  }

  @Test
  func thePanelStaysOnTheDisplayOfSystemSettings() {
    let size = OnboardingWindowController.panelSize
    let main = CGRect(x: 0, y: 0, width: 1_440, height: 900)
    let second = CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080)
    let settings = CGRect(x: 1_600, y: 300, width: 700, height: 600)
    let frame = OnboardingWindowController.panelFrame(next: settings, size: size, screens: [main, second])
    #expect(second.contains(frame))
    #expect(frame.minX == settings.maxX + 12)
  }
}
