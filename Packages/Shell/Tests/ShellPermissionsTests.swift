import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import VortexShell

/// Features as they declare their needs; ids as in the app.
private enum Needing {
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
}

struct PermissionCatalogTests {
  @Test
  func needsComeFromEnabledFeaturesInSidebarOrderAndKeyboardCleaningWhileHomeIsOn() {
    let catalog = PermissionCatalog(features: Needing.all, required: [])
    #expect(catalog.entries.map(\.permission) == [.notifications, .accessibility, .screenRecording, .pasteboard])
    #expect(catalog.entry(for: .notifications)?.needs.map(\.owner) == [.feature("timer"), .feature("secrets")])
    #expect(catalog.entry(for: .notifications)?.reasons == Needing.timer.permissionNeeds.map(\.reason) + Needing.keys.permissionNeeds.map(\.reason))
    #expect(catalog.entry(for: .accessibility)?.needs.map(\.owner) == [.keyboardCleaning])
    #expect(catalog.entry(for: .accessibility)?.reasons == [PermissionCatalog.keyboardCleaningReason])
    #expect(catalog.entry(for: .screenRecording)?.needs.map(\.owner) == [.feature("tasks")])
    #expect(catalog.entry(for: .pasteboard)?.needs.map(\.owner) == [.feature("clipboard")])
    // Those a feature's yellow dot names: keyboard cleaning's Accessibility isn't one.
    #expect(catalog.featurePermissions == [.notifications, .screenRecording, .pasteboard])
  }

  /// The keyboard button is on Home: without it, keyboard cleaning needs nothing.
  @Test
  func withoutHomeKeyboardCleaningNeedsNothing() {
    let catalog = PermissionCatalog(features: [Needing.timer], required: [])
    #expect(catalog.entries.map(\.permission) == [.notifications])
    #expect(catalog.entry(for: .accessibility) == nil)
  }

  @Test
  func featuresThatAreOffNeedNothing() {
    var settings = ShellSettings()
    settings.disabledFeatures = ["tasks", "timer"]
    let state = ShellFeature.State(settings: settings, features: Needing.all)
    #expect(state.permissionCatalog.entries.map(\.permission) == [.notifications, .accessibility, .pasteboard])
    #expect(state.permissionCatalog.entry(for: .notifications)?.needs.map(\.owner) == [.feature("secrets")])
  }

  /// A required permission nothing enabled needs has no page, so it can never block.
  @Test
  func requiredCountsOnlyForWhatIsNeeded() {
    let catalog = PermissionCatalog(features: [Needing.timer], required: [.accessibility, .screenRecording, .notifications])
    #expect(catalog.entries.map(\.isRequired) == [true])
    let allOff = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, PermissionStatus.notGranted) })
    #expect(catalog.missingRequired(allOff) == [.notifications])
  }

  /// `grantedAfterRestart` counts as on, `notNeeded` as satisfied, and a status not read yet as nothing.
  @Test
  func onlyARequiredPermissionThatReadsNotGrantedIsMissing() {
    let catalog = PermissionCatalog(features: Needing.all, required: Set(Permission.allCases))
    #expect(catalog.missingRequired([
      .notifications: .notGranted, .accessibility: .granted, .screenRecording: .grantedAfterRestart, .pasteboard: .notNeeded,
    ]) == [.notifications])
    #expect(catalog.missingRequired([:]).isEmpty)
    #expect(catalog.missingRequired([.accessibility: .notGranted, .pasteboard: .notGranted]) == [.accessibility, .pasteboard])
  }

  @Test
  func nothingIsRequiredForNow() {
    #expect(OnboardingConfig.requiredPermissions.isEmpty)
    #expect(ShellFeature.State().requiredPermissions == OnboardingConfig.requiredPermissions)
  }
}

@MainActor
struct ShellPermissionsTests {
  static let allOff: [Permission: PermissionStatus] = [
    .notifications: .notGranted, .accessibility: .notGranted, .screenRecording: .notGranted, .pasteboard: .notNeeded,
  ]

  func makeStore(
    features: [FeatureDescriptor] = Needing.all,
    disabled: [FeatureID] = [],
    required: Set<Permission> = []
  ) -> TestStoreOf<ShellFeature> {
    var settings = ShellSettings()
    settings.disabledFeatures = disabled
    var state = ShellFeature.State(settings: settings, features: features, onboarding: .finished)
    state.requiredPermissions = required
    state.onboardingContext.apply(to: &state.onboarding)
    return TestStore(initialState: state) {
      ShellFeature()
    } withDependencies: {
      $0.continuousClock = ImmediateClock()
      $0.settingsClient.save = { _ in }
      $0.featuresClient.setEnabled = { _, _ in }
      $0.onboardingProgress.save = { _ in }
      $0.onboardingWindow.present = { _, _ in }
      $0.onboardingWindow.hide = { _ in }
      $0.permissionsClient.setFrequentChecks = { _ in }
      $0.windowClient.dismiss = {}
    }
  }

  /// The first read reaches the onboarding: its statuses, then the launch's decision, which records this version and
  /// what macOS grants.
  func firstRead(_ store: TestStoreOf<ShellFeature>, _ statuses: [Permission: PermissionStatus]) async {
    await store.send(.permissionStatusesChanged(statuses)) {
      $0.$permissionStatuses.withLock { $0 = statuses }
    }
    await store.receive(\.onboarding.statusesChanged)
    await store.receive(\.onboarding.launched) { state in
      Self.recordsTheLaunch(&state, statuses)
    }
  }

  /// What the launch records: this version, and each permission macOS grants now, also for after a relaunch.
  static func recordsTheLaunch(_ state: inout ShellFeature.State, _ statuses: [Permission: PermissionStatus]) {
    let version = state.appVersion.full
    state.onboarding.progress.version = version
    for (permission, status) in statuses where status == .granted || status == .grantedAfterRestart {
      state.onboarding.progress.granted[permission] = version
    }
  }

  /// Everything the launch task starts besides the permissions, finished at once.
  func launchedQuietly(_ store: TestStoreOf<ShellFeature>) {
    store.dependencies.windowClient.events = { .finished }
    store.dependencies.windowClient.setMenuBarIconVisible = { _ in }
    store.dependencies.windowClient.setAcceptsFiles = { _ in }
    store.dependencies.hotkeyClient.presses = { _ in .finished }
    store.dependencies.systemClient.applyTheme = { _ in }
    store.dependencies.activeAppClient.activations = { .finished }
    store.dependencies.activeAppClient.terminations = { .finished }
    store.dependencies.launchAtLoginClient.status = { .disabled }
    store.dependencies.systemSettingsNamesClient.names = { SystemSettingsNames() }
  }

  // MARK: The statuses

  #if DEBUG
    @Test
    func theShellKeepsWhatMacOSSaysInTheSharedStatusesFromLaunchOn() async {
      let mac = SimulatedPermissions()
      let store = makeStore()
      launchedQuietly(store)
      store.dependencies.permissionsClient = .simulated(mac)
      store.dependencies.permissionPage.requests = { .finished }
      store.exhaustivity = .off

      let launch = await store.send(.task)
      await store.receive(\.permissionStatusesChanged)
      @Shared(.permissionStatuses) var statuses
      #expect(statuses == Self.allOff)

      mac.toggle(.accessibility, on: true)
      await store.receive(\.permissionStatusesChanged)
      #expect(statuses[.accessibility] == .granted)
      await launch.cancel()
    }

    /// A request shows the permission's page and asks macOS nothing by itself.
    @Test
    func aPageRequestShowsThePageAndAsksMacOSNothing() async {
      let mac = SimulatedPermissions()
      let store = makeStore()
      store.dependencies.permissionsClient = .simulated(mac)
      store.dependencies.permissionsClient.setFrequentChecks = { _ in }
      await store.send(.permissionPageRequested(.screenRecording))
      await store.receive(\.onboarding.pageRequested) {
        $0.onboarding.presentation = .single(.init(permission: .screenRecording, kind: .request), .window)
      }
      await store.finish()
      #expect(mac.state.events.isEmpty)
    }
  #endif

  @Test
  func aPageAFeatureAsksForReachesTheShell() async {
    let (requests, sendRequest) = AsyncStream.makeStream(of: Permission.self)
    let asked = AsyncStream.makeStream(of: Permission.self)
    let store = makeStore()
    launchedQuietly(store)
    store.dependencies.permissionsClient.updates = { .finished }
    store.dependencies.permissionsClient.request = { asked.continuation.yield($0) }
    store.dependencies.permissionPage.requests = { requests }
    store.exhaustivity = .off

    let launch = await store.send(.task)
    sendRequest.yield(.screenRecording)
    await store.receive(\.permissionPageRequested)
    await store.receive(\.onboarding.pageRequested)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .screenRecording, kind: .request), .window))
    await launch.cancel()
  }

  // MARK: Blocked

  /// Blocked at the first read: the launch opens the blocking page; the grant closes it after ✓.
  @Test
  func vortexIsBlockedWhileARequiredPermissionSomethingNeedsIsOff() async {
    let store = makeStore(required: [.accessibility])
    await store.send(.permissionStatusesChanged(Self.allOff)) {
      $0.$permissionStatuses.withLock { $0 = Self.allOff }
      $0.$appBlocked.withLock { $0 = true }
    }
    await store.receive(\.onboarding.statusesChanged)
    await store.receive(\.onboarding.launched) {
      Self.recordsTheLaunch(&$0, Self.allOff)
      $0.onboarding.presentation = .single(.init(permission: .accessibility, kind: .blocked), .window)
    }
    let granted = Self.allOff.merging([.accessibility: .granted]) { $1 }
    await store.send(.permissionStatusesChanged(granted)) {
      $0.$permissionStatuses.withLock { $0 = granted }
      $0.$appBlocked.withLock { $0 = false }
    }
    await store.receive(\.onboarding.statusesChanged) {
      // A grant is kept with this version.
      $0.onboarding.progress.granted[.accessibility] = $0.appVersion.full
      $0.onboarding.presentation = .single(.init(permission: .accessibility, kind: .blocked, isClosing: true), .window)
    }
    await store.receive(\.onboarding.singleCloseElapsed) {
      $0.onboarding.presentation = .hidden
    }
    await store.finish()
  }

  @Test
  func withNothingRequiredNothingBlocks() async {
    let store = makeStore()
    await firstRead(store, Self.allOff)
    #expect(!store.state.appBlocked)
  }

  @Test
  func nothingIsBlockedBeforeTheFirstRead() {
    let state = ShellFeature.State(features: Needing.all)
    var required = state
    required.requiredPermissions = Set(Permission.allCases)
    #expect(!required.isBlocked)
    #expect(!required.appBlocked)
  }

  /// Turning on a feature that needs a required permission that is off blocks at once, and opens the blocking page;
  /// turned off again, it unblocks, and the page stays until it is closed.
  @Test
  func turningOnAFeatureThatNeedsAMissingRequiredPermissionBlocksAtOnce() async {
    let store = makeStore(disabled: ["tasks"], required: [.screenRecording])
    await firstRead(store, Self.allOff)
    await store.send(.featureEnabledChanged("tasks", isEnabled: true)) {
      $0.settings.disabledFeatures = []
      $0.$appBlocked.withLock { $0 = true }
      $0.onboarding.catalog = $0.permissionCatalog
    }
    await store.receive(\.onboarding.blocked) {
      $0.onboarding.presentation = .single(.init(permission: .screenRecording, kind: .blocked), .window)
    }
    await store.send(.featureEnabledChanged("tasks", isEnabled: false)) {
      $0.settings.disabledFeatures = ["tasks"]
      $0.$appBlocked.withLock { $0 = false }
      $0.onboarding.catalog = $0.permissionCatalog
    }
    await store.finish()
  }

  /// Keyboard cleaning's Accessibility counts only while Home, with its button, is on.
  @Test
  func keyboardCleaningBlocksOnlyWhileHomeIsOn() async {
    let store = makeStore(disabled: ["home"], required: [.accessibility])
    await firstRead(store, Self.allOff)
    await store.send(.featureEnabledChanged("home", isEnabled: true)) {
      $0.settings.disabledFeatures = []
      $0.$appBlocked.withLock { $0 = true }
      $0.onboarding.catalog = $0.permissionCatalog
    }
    await store.receive(\.onboarding.blocked) {
      $0.onboarding.presentation = .single(.init(permission: .accessibility, kind: .blocked), .window)
    }
    await store.finish()
  }

  /// A permission macOS doesn't ask for, or one granted for after a relaunch, never blocks.
  @Test
  func notNeededAndGrantedAfterRestartNeverBlock() async {
    let store = makeStore(required: [.pasteboard, .screenRecording])
    let statuses: [Permission: PermissionStatus] = [
      .notifications: .notGranted, .accessibility: .notGranted, .screenRecording: .grantedAfterRestart, .pasteboard: .notNeeded,
    ]
    await firstRead(store, statuses)
    #expect(!store.state.appBlocked)
  }
}
