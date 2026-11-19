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
  static let keyboard = FeatureDescriptor(
    id: "keyboard", title: "Keyboard Cleaning", symbol: "keyboard", kind: .utility,
    permissionNeeds: [PermissionNeed(.accessibility, reason: "Locks the keyboard while you clean it.")]
  )
  static let all = [home, timer, tasks, clipboard, keys, keyboard]
}

struct PermissionCatalogTests {
  /// Every need comes from an enabled feature or utility, in sidebar order, with its own reason.
  @Test
  func needsComeFromEnabledFeaturesAndUtilitiesInSidebarOrder() {
    let catalog = PermissionCatalog(features: Needing.all, required: [])
    #expect(catalog.entries.map(\.permission) == [.notifications, .accessibility, .screenRecording, .pasteboard])
    #expect(catalog.entry(for: .notifications)?.needs.map(\.feature) == ["timer", "secrets"])
    #expect(catalog.entry(for: .notifications)?.reasons == Needing.timer.permissionNeeds.map(\.reason) + Needing.keys.permissionNeeds.map(\.reason))
    #expect(catalog.entry(for: .accessibility)?.needs.map(\.feature) == ["keyboard"])
    #expect(catalog.entry(for: .accessibility)?.reasons == Needing.keyboard.permissionNeeds.map(\.reason))
    #expect(catalog.entry(for: .screenRecording)?.needs.map(\.feature) == ["tasks"])
    #expect(catalog.entry(for: .pasteboard)?.needs.map(\.feature) == ["clipboard"])
  }

  /// Home needs nothing: Accessibility comes only with keyboard cleaning, the utility that locks the keyboard.
  @Test
  func homeNeedsNothingAccessibilityComesWithKeyboardCleaning() {
    let catalog = PermissionCatalog(features: [Needing.home, Needing.timer], required: [])
    #expect(catalog.entries.map(\.permission) == [.notifications])
    #expect(catalog.entry(for: .accessibility) == nil)
  }

  @Test
  func featuresThatAreOffNeedNothing() {
    var settings = ShellSettings()
    settings.addedFeatures = Needing.all.map(\.id).filter { !["tasks", "timer"].contains($0) }
    let state = ShellFeature.State(settings: settings, features: Needing.all)
    #expect(state.permissionCatalog.entries.map(\.permission) == [.notifications, .accessibility, .pasteboard])
    #expect(state.permissionCatalog.entry(for: .notifications)?.needs.map(\.feature) == ["secrets"])
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
    settings.addedFeatures = features.map(\.id).filter { !disabled.contains($0) }
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
      $0.windowClient.setHiddenIndicatorOwners = { _ in }
      $0.windowClient.setSize = { _ in }
      $0.hotkeyClient.presses = { _ in .finished }
      $0.launchGuard.beginTrial = { _ in }
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

  /// What the launch records: this version, and each signature-bound permission (Accessibility, Screen Recording)
  /// macOS grants now, also for after a relaunch.
  static func recordsTheLaunch(_ state: inout ShellFeature.State, _ statuses: [Permission: PermissionStatus]) {
    let version = state.appVersion.full
    state.onboarding.progress.version = version
    for (permission, status) in statuses
    where [.accessibility, .screenRecording].contains(permission) && (status == .granted || status == .grantedAfterRestart) {
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

  /// A page a feature asks for reaches the shell, and so does the page of a permission macOS refused while it reads
  /// granted, which says to turn the switch off and on again.
  @Test
  func aPageAFeatureAsksForReachesTheShell() async {
    let (requests, sendRequest) = AsyncStream.makeStream(of: PermissionPage.Request.self)
    let asked = AsyncStream.makeStream(of: Permission.self)
    let store = makeStore()
    launchedQuietly(store)
    store.dependencies.permissionsClient.updates = { .finished }
    store.dependencies.permissionsClient.request = { asked.continuation.yield($0) }
    store.dependencies.permissionPage.requests = { requests }
    store.exhaustivity = .off

    let launch = await store.send(.task)
    sendRequest.yield(.page(.screenRecording))
    await store.receive(\.permissionPageRequested)
    await store.receive(\.onboarding.pageRequested)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .screenRecording, kind: .request), .window))
    sendRequest.yield(.refused(.accessibility))
    await store.receive(\.refusedPageRequested)
    await store.receive(\.onboarding.pageRequested)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .accessibility, kind: .lockRefused), .window))
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
    await store.send(.featureAdded("tasks")) {
      $0.settings.addedFeatures = ["home", "timer", "tasks", "clipboard", "secrets", "keyboard"]
      $0.settings.lastTab = "feature:tasks"
      $0.$appBlocked.withLock { $0 = true }
      $0.onboarding.catalog = $0.permissionCatalog
    }
    await store.receive(\.onboarding.blocked) {
      $0.onboarding.presentation = .single(.init(permission: .screenRecording, kind: .blocked), .window)
    }
    await store.send(.featureRemoved("tasks")) {
      $0.settings.addedFeatures = ["home", "timer", "clipboard", "secrets", "keyboard"]
      $0.removedForUndo = "tasks"
      $0.$appBlocked.withLock { $0 = false }
      $0.onboarding.catalog = $0.permissionCatalog
    }
    await store.receive(\.undoExpired) { $0.removedForUndo = nil }
    await store.finish()
  }

  /// Accessibility counts only while keyboard cleaning, the utility that needs it, is added: added, a required one
  /// that is off blocks at once.
  @Test
  func keyboardCleaningsAccessibilityBlocksOnlyWhileItIsAdded() async {
    let store = makeStore(disabled: ["keyboard"], required: [.accessibility])
    await firstRead(store, Self.allOff)
    #expect(!store.state.appBlocked)
    await store.send(.featureAdded("keyboard")) {
      $0.settings.addedFeatures = ["home", "timer", "tasks", "clipboard", "secrets", "keyboard"]
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
