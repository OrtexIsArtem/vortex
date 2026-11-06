import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import VortexShell

/// The shell around the onboarding: entry points while blocked, becoming blocked by any route,
/// the notch window giving way to a page, keyboard cleaning during a revoke, the menu bar icon,
/// the first read and Done's hint.
@MainActor
struct ShellOnboardingTests {
  let clock = TestClock()
  /// The notch window: "present:<reason>" and "dismiss".
  let notchWindow = CallLog()
  /// The onboarding window: "window", "window+activate", "panel", "hide".
  let onboardingWindow = CallLog()
  let quits = CallLog()

  func makeStore(
    progress: OnboardingProgress = .finished,
    required: Set<Permission> = [],
    disabled: [FeatureID] = [],
    statuses: [Permission: PermissionStatus]? = OnboardingNeeds.allOff,
    appVersion: AppVersion = Self.thisVersion,
    askedBefore: Set<Permission> = []
  ) -> TestStoreOf<ShellFeature> {
    @Shared(.permissionStatuses) var shared
    $shared.withLock { $0 = statuses ?? [:] }
    var settings = ShellSettings()
    settings.disabledFeatures = disabled
    var state = ShellFeature.State(
      settings: settings,
      features: OnboardingNeeds.all + [.shelf],
      onboarding: progress,
      appVersion: appVersion,
      askedBefore: askedBefore
    )
    state.requiredPermissions = required
    state.onboarding.catalog = state.permissionCatalog
    let store = TestStore(initialState: state) {
      ShellFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.windowClient.present = { [notchWindow] reason in notchWindow.record("present:\(reason)") }
      $0.windowClient.dismiss = { [notchWindow] in notchWindow.record("dismiss") }
      $0.windowClient.setMenuBarIconVisible = { _ in }
      $0.windowClient.setAcceptsFiles = { _ in }
      $0.windowClient.holdKeyboard = { _ in }
      $0.settingsClient.save = { _ in }
      $0.featuresClient.setEnabled = { _, _ in }
      $0.onboardingProgress.save = { _ in }
      $0.onboardingWindow.present = { [onboardingWindow] mode, activate in
        onboardingWindow.record(mode.rawValue + (activate ? "+activate" : ""))
      }
      $0.onboardingWindow.hide = { [onboardingWindow] _ in onboardingWindow.record("hide") }
      $0.permissionsClient.refresh = {}
      $0.permissionsClient.setFrequentChecks = { _ in }
      $0.launchAtLoginClient.status = { .disabled }
      $0.launchAtLoginClient.isSetUp = { false }
      $0.hotkeyClient.shortcut = { _ in nil }
      $0.systemClient.quit = { [quits] in quits.record("quit") }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    return store
  }

  // MARK: - Blocked

  @Test
  func whileBlockedEveryEntryPointOpensTheBlockingPageAndNeverTheNotchWindow() async {
    let store = makeStore(required: [.accessibility])
    #expect(store.state.isBlocked)
    func entry(_ action: ShellFeature.Action) async {
      await store.send(action)
      await store.receive(\.onboarding.blockedEntry)
      #expect(store.state.onboarding.presentation == .single(.init(permission: .accessibility, kind: .blocked), .window))
      #expect(store.state.openReason == nil)
      #expect(await onboardingWindow.next() == "window+activate")
      await store.send(.onboarding(.closeTapped))
      #expect(await onboardingWindow.next() == "hide")
    }
    await entry(.openHotkeyPressed)
    await entry(.window(.menuBarIconClicked))
    await entry(.menuOpenTapped)
    await entry(.menuSettingsTapped)
    await entry(.featureHotkeyPressed("timer"))
    await entry(.window(.notchClicked(feature: nil)))
    // A file dragged onto the notch too.
    await entry(.window(.fileDragEnteredNotch))
    // A hover shows the page without activating Vortex.
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .milliseconds(300))
    await store.receive(\.hoverDelayElapsed)
    await store.receive(\.onboarding.blockedEntry)
    #expect(store.state.openReason == nil)
    #expect(await onboardingWindow.next() == "window")
    // «Quit Vortex» still works.
    await store.send(.quitButtonTapped)
    #expect(await quits.next() == "quit")
    // The notch window was asked to close each time, never to open.
    #expect(!notchWindow.all.contains { $0.hasPrefix("present") })
  }

  @Test
  func aRevokeWhileTheNotchWindowIsOpenClosesItAndOpensTheBlockingPage() async {
    let store = makeStore(required: [.accessibility], statuses: OnboardingNeeds.allOn)
    #expect(!store.state.isBlocked)
    await store.send(.openHotkeyPressed)
    #expect(store.state.openReason == .hotkey)
    #expect(await notchWindow.next() == "present:hotkey")
    var revoked = OnboardingNeeds.allOn
    revoked[.accessibility] = .notGranted
    await store.send(.permissionStatusesChanged(revoked))
    #expect(store.state.openReason == nil)
    #expect(store.state.appBlocked)
    #expect(await notchWindow.next() == "dismiss")
    await store.receive(\.onboarding.blocked)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .accessibility, kind: .blocked), .window))
    // Granted again: the page closes 1.5 s after ✓, and the notch window opens again.
    await store.send(.permissionStatusesChanged(OnboardingNeeds.allOn))
    #expect(!store.state.appBlocked)
    await clock.advance(by: .milliseconds(1_500))
    await store.receive(\.onboarding.singleCloseElapsed)
    #expect(store.state.onboarding.presentation == .hidden)
    await store.send(.openHotkeyPressed)
    #expect(store.state.openReason == .hotkey)
  }

  /// Turning on a feature that needs a required permission that is off blocks at once: the notch window closes and the
  /// blocking page opens.
  @Test
  func turningOnAFeatureThatNeedsAMissingRequiredPermissionClosesTheWindowAndOpensThePage() async {
    let store = makeStore(required: [.screenRecording], disabled: ["tasks"])
    #expect(!store.state.isBlocked)
    await store.send(.openHotkeyPressed)
    #expect(await notchWindow.next() == "present:hotkey")
    await store.send(.featureEnabledChanged("tasks", isEnabled: true))
    #expect(store.state.appBlocked)
    #expect(store.state.openReason == nil)
    #expect(await notchWindow.next() == "dismiss")
    await store.receive(\.onboarding.blocked)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .screenRecording, kind: .blocked), .window))
    #expect(await onboardingWindow.next() == "window+activate")
  }

  /// A new required set blocks the same way, and an unfinished onboarding jumps to the page of the missing permission.
  @Test
  func aNewRequiredSetBlocksAndTheOnboardingJumpsToThePage() async {
    let store = makeStore(progress: .at(.basics))
    await store.send(.binding(.set(\.requiredPermissions, [.accessibility])))
    #expect(store.state.appBlocked)
    await store.receive(\.onboarding.blocked)
    #expect(store.state.onboarding.presentation == .flow(.window))
    #expect(store.state.onboarding.page == .permission(.accessibility))
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
    #expect(blocked.state.onboarding.presentation == .single(.init(permission: .accessibility, kind: .blocked), .window))
  }

  // MARK: - Pages

  /// «Continue setup» closes the notch window before the onboarding comes forward.
  @Test
  func continueSetupClosesTheNotchWindowFirst() async {
    let store = makeStore(progress: .at(.basics))
    await store.send(.openHotkeyPressed)
    #expect(await notchWindow.next() == "present:hotkey")
    await store.send(.continueSetupTapped)
    #expect(store.state.openReason == nil)
    #expect(await notchWindow.next() == "dismiss")
    await store.receive(\.onboarding.continueSetupTapped)
    #expect(store.state.onboarding.presentation == .flow(.window))
    #expect(await onboardingWindow.next() == "window+activate")

    // Once the onboarding is done, the menu item isn't there, and nothing changes.
    let done = makeStore(progress: .finished)
    await done.send(.openHotkeyPressed)
    await done.send(.continueSetupTapped)
    #expect(done.state.openReason == .hotkey)
  }

  /// A notch window opened before the first read closes when the onboarding window shows then.
  @Test
  func aNotchWindowOpenAtTheFirstReadClosesWhenTheOnboardingShows() async {
    let store = makeStore(progress: .at(.welcome), statuses: nil)
    await store.send(.openHotkeyPressed)
    #expect(store.state.openReason == .hotkey)
    await store.send(.permissionStatusesChanged(OnboardingNeeds.allOff))
    #expect(store.state.openReason == nil)
    await store.receive(\.onboarding.launched)
    #expect(store.state.onboarding.presentation == .flow(.window))

    // Done already, nothing shows at the first read, and the notch window stays.
    let done = makeStore(progress: .finished, statuses: nil)
    await done.send(.openHotkeyPressed)
    await done.send(.permissionStatusesChanged(OnboardingNeeds.allOff))
    #expect(done.state.openReason == .hotkey)
  }

  @Test
  func aPageRequestClosesTheNotchWindowFirst() async {
    let store = makeStore()
    await store.send(.openHotkeyPressed)
    #expect(await notchWindow.next() == "present:hotkey")
    await store.send(.permissionPageRequested(.screenRecording))
    #expect(await notchWindow.next() == "dismiss")
    await store.receive(\.onboarding.pageRequested)
    #expect(store.state.openReason == nil)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .screenRecording, kind: .request), .window))
  }

  @Test
  func theFirstReadShowsAnUnfinishedOnboardingAtItsSavedPage() async {
    let store = makeStore(progress: .at(.permission(.screenRecording)), statuses: nil)
    await store.send(.permissionStatusesChanged(OnboardingNeeds.allOff))
    await store.receive(\.onboarding.launched)
    #expect(store.state.onboarding.presentation == .flow(.window))
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

  // MARK: - Keyboard cleaning

  @Test
  func anotherRequiredLossDuringTheLockWaitsForTheKeyboard() async {
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
    // «Turn the keyboard back on»: the window closes, and only now Vortex is blocked.
    await store.send(.keyboardCleaning(.stopTapped))
    #expect(store.state.openReason == nil)
    await store.receive(\.onboarding.blocked)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .screenRecording, kind: .blocked), .window))
  }

  @Test
  func losingAccessibilityDuringTheLockEndsItAndOpensNothing() async {
    let store = makeStore(statuses: OnboardingNeeds.allOn)
    store.dependencies.keyboardLockClient.lock = { true }
    store.dependencies.keyboardLockClient.unlock = {}
    await store.send(.openHotkeyPressed)
    await store.send(.keyboardCleaning(.startTapped))
    var lost = OnboardingNeeds.allOn
    lost[.accessibility] = .notGranted
    await store.send(.permissionStatusesChanged(lost))
    await store.receive(\.keyboardCleaning.accessLost)
    #expect(!store.state.keyboardCleaning.isLocked)
    #expect(store.state.openReason == .hotkey)
    #expect(store.state.onboarding.presentation == .hidden)
  }

  /// Required Accessibility lost during a lock: the lock ends at once, and Vortex is blocked then.
  @Test
  func losingRequiredAccessibilityDuringTheLockEndsItAndOpensTheBlockingPage() async {
    let store = makeStore(required: [.accessibility], statuses: OnboardingNeeds.allOn)
    store.dependencies.keyboardLockClient.lock = { true }
    store.dependencies.keyboardLockClient.unlock = {}
    await store.send(.openHotkeyPressed)
    await store.send(.keyboardCleaning(.startTapped))
    var lost = OnboardingNeeds.allOn
    lost[.accessibility] = .notGranted
    await store.send(.permissionStatusesChanged(lost))
    // Still locked when the statuses arrive: nothing yet.
    #expect(store.state.onboarding.presentation == .hidden)
    await store.receive(\.keyboardCleaning.accessLost)
    #expect(!store.state.keyboardCleaning.isLocked)
    #expect(store.state.openReason == nil)
    await store.receive(\.onboarding.blocked)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .accessibility, kind: .blocked), .window))
  }

  @Test
  func keyboardCleaningWithoutAccessOpensThePageAfterClosingTheNotchWindow() async {
    let store = makeStore()
    await store.send(.openHotkeyPressed)
    await store.send(.keyboardCleaning(.startTapped))
    await store.receive(\.keyboardCleaning.delegate)
    await store.receive(\.onboarding.pageRequested)
    #expect(store.state.openReason == nil)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .accessibility, kind: .request), .window))
  }

  // MARK: - The menu bar icon and Done's hint

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
  func donesHintNamesTheNotchWhileANotchDisplayIsConnected() async {
    let store = makeStore()
    #expect(store.state.onboarding.doneHint == .init(notch: .hover, menuBarIcon: true))
    // A notch display next to one without: the notch is still a way in, and the icon shows.
    await store.send(.window(.screensChanged(everyScreenHasNotch: false, anyScreenHasNotch: true)))
    #expect(store.state.onboarding.doneHint == .init(notch: .hover, menuBarIcon: true))
    // No notch display at all: only the menu bar.
    await store.send(.window(.screensChanged(everyScreenHasNotch: false, anyScreenHasNotch: false)))
    #expect(store.state.onboarding.doneHint == .init(notch: nil, menuBarIcon: true))
    // Notch only, hover off, icon hidden: the notch click.
    await store.send(.window(.screensChanged(everyScreenHasNotch: true, anyScreenHasNotch: true)))
    await store.send(.binding(.set(\.settings.showMenuBarIcon, false)))
    await store.send(.binding(.set(\.settings.openOnHover, false)))
    #expect(store.state.onboarding.doneHint == .init(notch: .click, menuBarIcon: false))
  }

  // MARK: - After an update

  /// The version these stores run; the onboarding keeps it as "0.1.3 (6)".
  static let thisVersion = AppVersion(short: "0.1.3", build: "6")
  static let previous = "0.1.2 (5)"

  /// An onboarding finished under `version`, with these permissions granted then.
  static func finished(grantedBefore: [Permission], version: String = previous) -> OnboardingProgress {
    var progress = OnboardingProgress.finished
    progress.version = version
    for permission in grantedBefore {
      progress.granted[permission] = version
    }
    return progress
  }

  /// All on, except these.
  static func allOn(but off: Permission...) -> [Permission: PermissionStatus] {
    var statuses = OnboardingNeeds.allOn
    for permission in off {
      statuses[permission] = .notGranted
    }
    return statuses
  }

  /// The launch's first read, then its decision.
  func launch(_ store: TestStoreOf<ShellFeature>, _ statuses: [Permission: PermissionStatus]) async {
    await store.send(.permissionStatusesChanged(statuses))
    await store.receive(\.onboarding.launched)
  }

  /// A new signature: System Settings still shows Vortex on, macOS denies the new build. The page opens by itself,
  /// with the hint to turn the switch off and on at once.
  @Test
  func aPermissionTheUpdateDroppedOpensItsPageAtLaunchWithTheHintAtOnce() async {
    let store = makeStore(progress: Self.finished(grantedBefore: [.notifications, .screenRecording]), statuses: nil)
    await launch(store, Self.allOn(but: .screenRecording))
    #expect(store.state.onboarding.presentation == .single(.init(permission: .screenRecording, kind: .request), .window))
    #expect(await onboardingWindow.next() == "window+activate")
    #expect(store.state.onboarding.showsRecheckHint(.screenRecording))
    // This version is recorded after the check; the dropped grant stays as one from before.
    #expect(store.state.onboarding.progress.version == "0.1.3 (6)")
    #expect(store.state.onboarding.progress.granted == [
      .notifications: "0.1.3 (6)", .accessibility: "0.1.3 (6)", .screenRecording: Self.previous, .pasteboard: "0.1.3 (6)",
    ])
    // Granted again: ✓, and the page closes.
    await store.send(.permissionStatusesChanged(OnboardingNeeds.allOn))
    await store.receive(\.onboarding.statusesChanged)
    #expect(store.state.onboarding.progress.granted[.screenRecording] == "0.1.3 (6)")
    await clock.advance(by: .milliseconds(1_500))
    await store.receive(\.onboarding.singleCloseElapsed)
    #expect(store.state.onboarding.presentation == .hidden)
  }

  /// Several pages open one after another in onboarding order: the next when one is closed or granted, skipping one
  /// granted meanwhile.
  @Test
  func severalPagesOpenOneAfterAnotherInOnboardingOrder() async {
    let store = makeStore(progress: Self.finished(grantedBefore: [.notifications, .screenRecording]), statuses: nil)
    await launch(store, Self.allOn(but: .notifications, .screenRecording))
    #expect(store.state.onboarding.presentation == .single(.init(permission: .notifications, kind: .request), .window))
    #expect(store.state.onboarding.afterUpdate == [.screenRecording])
    await store.send(.onboarding(.closeTapped))
    #expect(store.state.onboarding.presentation == .single(.init(permission: .screenRecording, kind: .request), .window))
    await store.send(.onboarding(.closeTapped))
    #expect(store.state.onboarding.presentation == .hidden)

    let granting = makeStore(progress: Self.finished(grantedBefore: [.notifications, .screenRecording]), statuses: nil)
    await launch(granting, Self.allOn(but: .notifications, .screenRecording))
    await granting.send(.permissionStatusesChanged(Self.allOn(but: .screenRecording)))
    await granting.receive(\.onboarding.statusesChanged)
    await clock.advance(by: .milliseconds(1_500))
    await granting.receive(\.onboarding.singleCloseElapsed)
    #expect(granting.state.onboarding.presentation == .single(.init(permission: .screenRecording, kind: .request), .window))

    let meanwhile = makeStore(progress: Self.finished(grantedBefore: [.notifications, .screenRecording]), statuses: nil)
    await launch(meanwhile, Self.allOn(but: .notifications, .screenRecording))
    await meanwhile.send(.permissionStatusesChanged(Self.allOn(but: .notifications)))
    await meanwhile.receive(\.onboarding.statusesChanged)
    await meanwhile.send(.onboarding(.closeTapped))
    #expect(meanwhile.state.onboarding.presentation == .hidden)
  }

  /// Checked once per version: the next launch of the same version opens nothing, and the dot stays. The page, when a
  /// feature asks for it, still says at once to turn the switch off and on.
  @Test
  func theCheckRunsOncePerVersion() async {
    let store = makeStore(progress: Self.finished(grantedBefore: [.screenRecording]), statuses: nil)
    await launch(store, Self.allOn(but: .screenRecording))
    await store.send(.onboarding(.closeTapped))
    let next = makeStore(progress: store.state.onboarding.progress, statuses: nil)
    await launch(next, Self.allOn(but: .screenRecording))
    #expect(next.state.onboarding.presentation == .hidden)
    await next.send(.permissionPageRequested(.screenRecording))
    await next.receive(\.onboarding.pageRequested)
    #expect(next.state.onboarding.showsRecheckHint(.screenRecording))
  }

  /// Turned off under the version that granted it, a permission is the user's choice: no page after the next update,
  /// and no hint at once.
  @Test
  func aPermissionTurnedOffUnderTheVersionThatGrantedItIsForgotten() async {
    let store = makeStore(progress: Self.finished(grantedBefore: []), statuses: nil)
    await launch(store, OnboardingNeeds.allOn)
    #expect(store.state.onboarding.progress.granted[.screenRecording] == "0.1.3 (6)")
    await store.send(.permissionStatusesChanged(Self.allOn(but: .screenRecording)))
    await store.receive(\.onboarding.statusesChanged)
    #expect(store.state.onboarding.progress.granted[.screenRecording] == nil)
    #expect(!store.state.onboarding.showsRecheckHint(.screenRecording))

    let updated = makeStore(
      progress: store.state.onboarding.progress, statuses: nil, appVersion: AppVersion(short: "0.1.4", build: "7")
    )
    await launch(updated, Self.allOn(but: .screenRecording))
    #expect(updated.state.onboarding.presentation == .hidden)
  }

  /// Without another version or build, nothing opens.
  @Test
  func withoutAnUpdateNothingOpens() async {
    let store = makeStore(progress: Self.finished(grantedBefore: [.screenRecording], version: "0.1.3 (6)"), statuses: nil)
    await launch(store, Self.allOn(but: .screenRecording))
    #expect(store.state.onboarding.presentation == .hidden)
  }

  /// Only permissions with a yellow dot open a page: keyboard cleaning's Accessibility waits for Home's button, whose
  /// page then says at once to turn the switch off and on.
  @Test
  func onlyPermissionsAFeatureNeedsOpenAPage() async {
    let store = makeStore(progress: Self.finished(grantedBefore: [.accessibility]), statuses: nil)
    await launch(store, Self.allOn(but: .accessibility))
    #expect(store.state.onboarding.presentation == .hidden)
    await store.send(.permissionPageRequested(.accessibility))
    await store.receive(\.onboarding.pageRequested)
    #expect(store.state.onboarding.showsRecheckHint(.accessibility))
  }

  /// An unfinished onboarding and blocked mode come first, and no page of the update waits after them.
  @Test
  func theOnboardingAndBlockedModeComeFirst() async {
    var unfinished = Self.finished(grantedBefore: [.screenRecording])
    unfinished.completed = false
    unfinished.page = OnboardingPage.basics.id
    let flow = makeStore(progress: unfinished, statuses: nil)
    await launch(flow, Self.allOn(but: .screenRecording))
    #expect(flow.state.onboarding.presentation == .flow(.window))
    #expect(flow.state.onboarding.afterUpdate.isEmpty)

    let blocked = makeStore(
      progress: Self.finished(grantedBefore: [.screenRecording]), required: [.accessibility], statuses: nil
    )
    await launch(blocked, Self.allOn(but: .accessibility, .screenRecording))
    #expect(blocked.state.onboarding.presentation == .single(.init(permission: .accessibility, kind: .blocked), .window))
    #expect(blocked.state.onboarding.afterUpdate.isEmpty)
    #expect(blocked.state.onboarding.progress.version == "0.1.3 (6)")
  }

  /// 0.1.1 and earlier kept no grants: what Vortex had asked macOS for counts as granted then.
  @Test
  func anInstallFromBeforeTheRecordsCountsWhatVortexHadAskedFor() async {
    let store = makeStore(progress: .finished, statuses: nil, askedBefore: [.screenRecording, .accessibility])
    await launch(store, Self.allOn(but: .notifications, .screenRecording))
    #expect(store.state.onboarding.presentation == .single(.init(permission: .screenRecording, kind: .request), .window))
    #expect(store.state.onboarding.afterUpdate.isEmpty)
    #expect(store.state.onboarding.progress.granted[.screenRecording] == OnboardingFeature.State.earlierVersion)
    #expect(store.state.onboarding.progress.granted[.accessibility] == "0.1.3 (6)")
    #expect(store.state.onboarding.progress.granted[.notifications] == nil)
    #expect(store.state.onboarding.showsRecheckHint(.screenRecording))
    #expect(!store.state.onboarding.showsRecheckHint(.notifications))

    // A fresh install shows the onboarding, whatever was asked.
    let fresh = makeStore(progress: OnboardingProgress(), statuses: nil, askedBefore: [.screenRecording])
    await launch(fresh, Self.allOn(but: .screenRecording))
    #expect(fresh.state.onboarding.presentation == .flow(.window))
  }

  /// A notch window opened before the first read closes when an update's page shows then.
  @Test
  func aNotchWindowOpenAtTheFirstReadClosesForAPageOfTheUpdate() async {
    let store = makeStore(progress: Self.finished(grantedBefore: [.screenRecording]), statuses: nil)
    await store.send(.openHotkeyPressed)
    #expect(store.state.openReason == .hotkey)
    await launch(store, Self.allOn(but: .screenRecording))
    #expect(store.state.openReason == nil)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .screenRecording, kind: .request), .window))
  }
}
