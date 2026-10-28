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
  }

  /// The keyboard button is on Home: without it, keyboard cleaning needs nothing (S54).
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

  /// A required permission nothing enabled needs has no page, so it can never block (S45, S66).
  @Test
  func requiredCountsOnlyForWhatIsNeeded() {
    let catalog = PermissionCatalog(features: [Needing.timer], required: [.accessibility, .screenRecording, .notifications])
    #expect(catalog.entries.map(\.isRequired) == [true])
    let allOff = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, PermissionStatus.notGranted) })
    #expect(catalog.missingRequired(allOff) == [.notifications])
  }

  /// `grantedAfterRestart` counts as on (S82), `notNeeded` as satisfied (S66), and a status not read yet as nothing.
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
    var state = ShellFeature.State(settings: settings, features: features)
    state.requiredPermissions = required
    return TestStore(initialState: state) {
      ShellFeature()
    } withDependencies: {
      $0.continuousClock = ImmediateClock()
      $0.settingsClient.save = { _ in }
      $0.featuresClient.setEnabled = { _, _ in }
    }
  }

  /// Everything the launch task starts besides the permissions, finished at once.
  func launchedQuietly(_ store: TestStoreOf<ShellFeature>) {
    store.dependencies.windowClient.events = { .finished }
    store.dependencies.windowClient.setMenuBarIconVisible = { _ in }
    store.dependencies.windowClient.setAcceptsFiles = { _ in }
    store.dependencies.hotkeyClient.presses = { _ in .finished }
    store.dependencies.systemClient.applyTheme = { _ in }
    store.dependencies.launchAtLoginClient.enableOnFirstLaunch = {}
    store.dependencies.launchAtLoginClient.status = { .disabled }
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

    /// Until the onboarding window shows the page, the request goes to macOS.
    @Test
    func forNowAPageRequestAsksMacOS() async {
      let mac = SimulatedPermissions()
      let store = makeStore()
      store.dependencies.permissionsClient = .simulated(mac)
      await store.send(.permissionPageRequested(.screenRecording))
      await store.finish()
      #expect(mac.state.events == [.prompt(.screenRecording)])
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
    var askedFor = asked.stream.makeAsyncIterator()
    #expect(await askedFor.next() == .screenRecording)
    await launch.cancel()
  }

  // MARK: Blocked (S9, S43)

  @Test
  func vortexIsBlockedWhileARequiredPermissionSomethingNeedsIsOff() async {
    let store = makeStore(required: [.accessibility])
    await store.send(.permissionStatusesChanged(Self.allOff)) {
      $0.$permissionStatuses.withLock { $0 = Self.allOff }
      $0.$appBlocked.withLock { $0 = true }
    }
    let granted = Self.allOff.merging([.accessibility: .granted]) { $1 }
    await store.send(.permissionStatusesChanged(granted)) {
      $0.$permissionStatuses.withLock { $0 = granted }
      $0.$appBlocked.withLock { $0 = false }
    }
  }

  @Test
  func withNothingRequiredNothingBlocks() async {
    let store = makeStore()
    await store.send(.permissionStatusesChanged(Self.allOff)) {
      $0.$permissionStatuses.withLock { $0 = Self.allOff }
    }
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

  /// Turning on a feature that needs a required permission that is off blocks at once (S45).
  @Test
  func turningOnAFeatureThatNeedsAMissingRequiredPermissionBlocksAtOnce() async {
    let store = makeStore(disabled: ["tasks"], required: [.screenRecording])
    await store.send(.permissionStatusesChanged(Self.allOff)) {
      $0.$permissionStatuses.withLock { $0 = Self.allOff }
    }
    await store.send(.featureEnabledChanged("tasks", isEnabled: true)) {
      $0.settings.disabledFeatures = []
      $0.$appBlocked.withLock { $0 = true }
    }
    await store.send(.featureEnabledChanged("tasks", isEnabled: false)) {
      $0.settings.disabledFeatures = ["tasks"]
      $0.$appBlocked.withLock { $0 = false }
    }
    await store.finish()
  }

  /// Keyboard cleaning's Accessibility counts only while Home, with its button, is on (S54).
  @Test
  func keyboardCleaningBlocksOnlyWhileHomeIsOn() async {
    let store = makeStore(disabled: ["home"], required: [.accessibility])
    await store.send(.permissionStatusesChanged(Self.allOff)) {
      $0.$permissionStatuses.withLock { $0 = Self.allOff }
    }
    await store.send(.featureEnabledChanged("home", isEnabled: true)) {
      $0.settings.disabledFeatures = []
      $0.$appBlocked.withLock { $0 = true }
    }
    await store.finish()
  }

  /// A permission macOS doesn't ask for, or one granted for after a relaunch, never blocks (S66, S82).
  @Test
  func notNeededAndGrantedAfterRestartNeverBlock() async {
    let store = makeStore(required: [.pasteboard, .screenRecording])
    let statuses: [Permission: PermissionStatus] = [
      .notifications: .notGranted, .accessibility: .notGranted, .screenRecording: .grantedAfterRestart, .pasteboard: .notNeeded,
    ]
    await store.send(.permissionStatusesChanged(statuses)) {
      $0.$permissionStatuses.withLock { $0 = statuses }
    }
    #expect(!store.state.appBlocked)
  }
}
