import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import VortexShell

/// The shell around the onboarding: entry points while blocked (S9, S43, S46, S64), becoming blocked by any route (S9,
/// S45), the notch window giving way to a page (S37), keyboard cleaning during a revoke (S38), the menu bar icon (S42),
/// the first read (S7) and Done's hint (S75).
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
    statuses: [Permission: PermissionStatus]? = OnboardingNeeds.allOff
  ) -> TestStoreOf<ShellFeature> {
    @Shared(.permissionStatuses) var shared
    $shared.withLock { $0 = statuses ?? [:] }
    var settings = ShellSettings()
    settings.disabledFeatures = disabled
    var state = ShellFeature.State(settings: settings, features: OnboardingNeeds.all + [.shelf], onboarding: progress)
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

  // MARK: - Blocked (S9, S43, S46)

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
    // A file dragged onto the notch too (S43).
    await entry(.window(.fileDragEnteredNotch))
    // A hover shows the page without activating Vortex (S46).
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .milliseconds(300))
    await store.receive(\.hoverDelayElapsed)
    await store.receive(\.onboarding.blockedEntry)
    #expect(store.state.openReason == nil)
    #expect(await onboardingWindow.next() == "window")
    // «Вийти з Vortex» still works.
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
  /// blocking page opens (S9, S45).
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

  /// A new required set blocks the same way, and an unfinished onboarding jumps to the page of the missing permission
  /// (S65).
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

  // MARK: - Pages (S7, S37)

  /// A-B4: «Продовжити налаштування» closes the notch window before the onboarding comes forward (S37).
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

  /// A notch window opened before the first read closes when the onboarding window shows then (S7, S37).
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

  // MARK: - Keyboard cleaning (S38)

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
    // «Увімкнути клавіатуру»: the window closes, and only now Vortex is blocked.
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

  /// Required Accessibility lost during a lock: the lock ends at once, and Vortex is blocked then (S9, S38).
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

  // MARK: - The menu bar icon (S42) and Done's hint (S75)

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
}
