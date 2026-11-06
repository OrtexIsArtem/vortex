import ComposableArchitecture
import Foundation
import VortexCore
import VortexPlatform

/// The first-run onboarding and the single permission page. The shell owns it:
/// it keeps `catalog`, `steps` and `doneHint` current, hands it the entry points while Vortex is blocked, and the
/// requests features make through `PermissionPage`.
@Reducer
struct OnboardingFeature {
  /// System Settings' bundle id: the guide panel sits next to its window.
  static let systemSettingsID = "com.apple.systempreferences"

  @ObservableState
  struct State: Equatable {
    /// Saved in DataFolder/onboarding.json on every change.
    var progress = OnboardingProgress()
    /// What the enabled features and the shell need, and what is required; the shell keeps it current.
    var catalog = PermissionCatalog(features: [], required: [])
    /// Enabled features that bring their own step, in sidebar order.
    var steps: [FeatureID] = []
    /// Every feature with a step, on or off, in sidebar order: where a step's page sits in the order.
    var stepOrder: [FeatureID] = []
    @SharedReader(.permissionStatuses) var statuses
    @SharedReader(.onboardingStepsDone) var stepsDone
    /// Whether the window shows, what, and as the full window or the guide panel.
    var presentation: Presentation = .hidden
    /// A "Turn on" click armed the panel: System Settings coming to the front within 10 s shrinks the window.
    var guideArmed: Permission?
    /// System Settings quit while a page showed: for 1 s, the app macOS brings forward in its place puts the window back
    /// in front each time it comes to the front, as it may take the front back after Vortex.
    var keepsFront = false
    /// The last app other than Vortex and System Settings to come to the front while a page showed: when System Settings
    /// quits, the one macOS brings forward. While nil, the first to come forward after the quit counts as that app.
    var lastApp: String?
    /// System Settings came to the front after a request from these pages.
    var settingsOpened: Set<Permission> = []
    /// Permissions whose check waited for this launch's relaunch: the pasteboard's page gives the recheck hint only
    /// once that relaunch still reads it off, as nothing before it can tell.
    var checkedAtLaunch: Set<Permission> = []
    /// "Click Allow in the notification…" under the notifications row, for 15 s or until the status changes.
    var isNotificationHintVisible = false
    /// "Turn on" ignores more clicks until the status changes, or for 2 s (15 s for notifications).
    var turnOnIgnored: Set<Permission> = []
    /// Navigation buttons ignore input for 300 ms after a page change.
    var isNavigationLocked = false
    /// A relaunch was asked for: until the process is gone, no other navigation or finish is taken.
    var isRelaunching = false
    var loginItem: LaunchAtLoginStatus = .disabled
    /// "Open at login" as the user set it on Basics, applied when they leave it; nil until they touch the switch.
    var openAtLoginChoice: Bool?
    /// Vortex set the login item up before, as every release build without the onboarding did: the switch starts
    /// from the real state, not from "on".
    var loginItemWasSetUp = false
    /// Release builds, and QA runs with release behavior, apply the login item choice.
    var appliesLoginItem = false
    /// Vortex's own bundle id: Vortex in front keeps the panel showing.
    var ownBundleID = Bundle.main.bundleIdentifier ?? ""
    /// What Done's hint names, from the settings and screens.
    var doneHint = DoneHint()
    /// The "Open Vortex" shortcut, read when Done shows; nil while none is set.
    var openShortcut: String?
    /// The pane names the drawn System Settings shows, as this Mac's System Settings has them; read once at launch.
    var settingsNames = SystemSettingsNames()
    /// This build's version, short version and build ("0.1.2 (17)"), as `progress` keeps it; the shell sets it.
    var appVersion = ""
    /// What Vortex had asked macOS for (Platform's permissions.json), read at launch: a release that kept no grants yet
    /// counts these as granted then (`grantedVersion`).
    var askedBefore: Set<Permission> = []
    /// After an update, the pages still to show, in onboarding order: the next opens when a single page closes.
    var afterUpdate: [Permission] = []

    init(progress: OnboardingProgress = OnboardingProgress()) {
      self.progress = progress
    }

    /// The permissions macOS ties to Vortex's signature: a new one drops them while System Settings still shows Vortex
    /// on. Notifications go by the bundle id, and the pasteboard never reads granted.
    static let signatureBound: Set<Permission> = [.accessibility, .screenRecording]

    /// The version that stands for a release that kept no grants: 0.1.1 and earlier.
    static let earlierVersion = "earlier"

    /// After an update, a version or build other than the last launch's: the signature-bound permissions with a yellow
    /// dot, needed by an enabled feature, that macOS reported granted under that last version and that read
    /// `notGranted` now, in onboarding order.
    var lostInUpdate: [Permission] {
      let previous = progress.version ?? Self.earlierVersion
      guard previous != appVersion else { return [] }
      return catalog.featurePermissions.filter { permission in
        Self.signatureBound.contains(permission) && statuses[permission] == .notGranted
          && grantedVersion(permission) == previous
      }
    }

    /// The version that last saw macOS grant a signature-bound `permission`; before any launch was recorded (0.1.1 and
    /// earlier), `earlierVersion` for one Vortex had asked for. Nil when macOS never granted it, as far as Vortex knows.
    func grantedVersion(_ permission: Permission) -> String? {
      if let version = progress.granted[permission] { return version }
      guard progress.version == nil, Self.signatureBound.contains(permission), askedBefore.contains(permission) else {
        return nil
      }
      return Self.earlierVersion
    }

    /// Records the launch, after its check for permissions the update dropped: this version, and what macOS grants now.
    /// Only signature-bound permissions are kept, and never a guess about a release that kept no grants: a page the
    /// update opened says to turn the switch off and on by itself.
    mutating func recordLaunch() {
      progress.version = appVersion
      recordGrants()
      progress.granted = progress.granted.filter { Self.signatureBound.contains($0.key) && $0.value != Self.earlierVersion }
    }

    /// What macOS says now about the signature-bound permissions, under this version: a grant, also one for after a
    /// relaunch, is kept with this version; one that reads `notGranted` under the version that saw it granted was
    /// turned off and is dropped. Returns whether anything changed.
    @discardableResult
    mutating func recordGrants() -> Bool {
      let before = progress.granted
      for (permission, status) in statuses where Self.signatureBound.contains(permission) {
        if status.isOn {
          progress.granted[permission] = appVersion
        } else if status == .notGranted, progress.granted[permission] == appVersion {
          progress.granted[permission] = nil
        }
      }
      return progress.granted != before
    }

    var isVisible: Bool { presentation != .hidden }
    var statusesRead: Bool { !statuses.isEmpty }

    /// Where the page shows: the window or the panel; nil while hidden.
    var surface: Surface? {
      switch presentation {
      case .hidden: nil
      case let .flow(surface), let .single(_, surface): surface
      }
    }

    var isPanel: Bool { guided != nil }
    /// The panel stepped aside while another app is in front.
    var isPanelHidden: Bool { surface?.isHidden == true }
    /// The permission the guide panel shows.
    var guided: Permission? {
      if case let .panel(permission, _) = surface { permission } else { nil }
    }

    var isFlow: Bool {
      if case .flow = presentation { true } else { false }
    }

    var single: SinglePage? {
      if case let .single(single, _) = presentation { single } else { nil }
    }

    /// Changes where a shown page is; nothing while hidden.
    mutating func setSurface(_ surface: Surface) {
      switch presentation {
      case .hidden: break
      case .flow: presentation = .flow(surface)
      case let .single(single, _): presentation = .single(single, surface)
      }
    }

    /// The required permissions that read `notGranted`, in the catalog's order.
    var missingRequired: [Permission] { catalog.missingRequired(statuses) }

    /// Every page of this onboarding, in order. A permission macOS doesn't ask for here has no page.
    var pages: [OnboardingPage] {
      var pages: [OnboardingPage] = [.welcome, .basics]
      pages += catalog.entries.map(\.permission)
        .filter { !$0.isGrantedInPlace && statuses[$0] != .notNeeded }
        .map(OnboardingPage.permission)
      pages += steps.map(OnboardingPage.step)
      pages.append(.done)
      return pages
    }

    /// Where a page sits in the order every onboarding follows; a step by its feature's place in the sidebar.
    func rank(_ page: OnboardingPage) -> Int {
      switch page {
      case .welcome: 0
      case .basics: 1
      case let .permission(permission): 2 + (Permission.allCases.firstIndex(of: permission) ?? 0)
      case let .step(feature): 100 + (stepOrder.firstIndex(of: feature) ?? stepOrder.count)
      case .done: 10_000
      }
    }

    /// The saved page; one that no longer exists resumes at the next page in order, else Done. A page id this
    /// build can't read starts at Welcome.
    var page: OnboardingPage {
      let pages = pages
      guard let saved = OnboardingPage(id: progress.page) else { return .welcome }
      if pages.contains(saved) { return saved }
      let savedRank = rank(saved)
      return pages.first { rank($0) > savedRank } ?? .done
    }

    /// The permissions with a row on a page: notifications on Basics, a hard page's own.
    func rows(on page: OnboardingPage) -> [Permission] {
      switch page {
      case .basics:
        catalog.entry(for: .notifications) != nil && statuses[.notifications] != .notNeeded ? [.notifications] : []
      case let .permission(permission): [permission]
      case .welcome, .step, .done: []
      }
    }

    /// One row per needed permission on Done.
    var doneRows: [Permission] {
      catalog.entries.map(\.permission).filter { statuses[$0] != .notNeeded }
    }

    func rowState(_ permission: Permission) -> PermissionRowState {
      if progress.pendingChecks.contains(permission) { return .afterRestart }
      switch statuses[permission] {
      case nil: return .unknown
      case .granted?, .notNeeded?: return .on
      case .grantedAfterRestart?: return .afterRestart
      case .notGranted?: return .off
      }
    }

    func isOn(_ permission: Permission) -> Bool {
      let state = rowState(permission)
      return state == .on || state == .afterRestart
    }

    /// A required permission that reads off shows "Required".
    func isRequiredMissing(_ permission: Permission) -> Bool {
      catalog.entry(for: permission)?.isRequired == true && statuses[permission] == .notGranted
    }

    /// The tag beside a row's title: "Required" for a required permission that is off, wherever it shows; "Optional"
    /// for one that is off and can be skipped, on the onboarding's pages, where Skip is there for it. Nothing
    /// before the first read, or once it is on.
    func rowTag(_ permission: Permission) -> RowTag? {
      if isRequiredMissing(permission) { return .required }
      guard isFlow, rowState(permission) == .off, catalog.entry(for: permission)?.isRequired == false else { return nil }
      return .optional
    }

    /// Next and Skip on the page shown.
    var buttons: Buttons {
      let page = page
      guard statusesRead else { return Buttons(nextVisible: false, nextEnabled: false, skipVisible: false) }
      switch page {
      case .welcome, .done:
        return Buttons(nextVisible: false, nextEnabled: false, skipVisible: false)
      case let .step(feature):
        let isDone = stepsDone.contains(feature)
        return Buttons(nextVisible: isDone, nextEnabled: isDone, skipVisible: !isDone)
      case .basics, .permission:
        let rows = rows(on: page)
        let off = rows.filter { !isOn($0) }
        return Buttons(
          nextVisible: true,
          nextEnabled: off.isEmpty,
          skipVisible: !off.isEmpty && !off.contains(where: isRequiredMissing)
        )
      }
    }

    /// Done's final button reads "Restart and start" while a grant waits for a relaunch, once per onboarding.
    var finishRestarts: Bool {
      guard !progress.restarted else { return false }
      return !progress.pendingChecks.isEmpty || doneRows.contains { statuses[$0] == .grantedAfterRestart }
    }

    /// Done's final button waits for every required permission.
    var finishEnabled: Bool {
      statusesRead && !doneRows.contains(where: isRequiredMissing)
    }

    /// The quiet "Restart now" link: a permission on the page works only after a relaunch, and Vortex hasn't
    /// relaunched during this onboarding yet.
    var showsRestartNow: Bool {
      guard isFlow, !progress.restarted else { return false }
      return rows(on: page).contains { statuses[$0] == .grantedAfterRestart }
    }

    /// "Restart to check" under the pasteboard once its pane was opened: on a single page always, in the
    /// onboarding only before its one restart.
    func showsRestartToCheck(_ permission: Permission) -> Bool {
      guard permission == .pasteboard, progress.pendingChecks.contains(.pasteboard) else { return false }
      return single != nil || !progress.restarted
    }

    /// A single page whose permission waits for a relaunch: ✓, "Restart Vortex" and "Later".
    var waitsForRelaunch: Bool {
      guard let single else { return false }
      return statuses[single.permission] == .grantedAfterRestart
    }

    /// The recheck hint: "Already on in System Settings? Turn it off and on again.", or on a page the refused lock
    /// opened, "If the switch is already on, turn it off and on again." It shows once System Settings came up for the
    /// page, and at once on a page an update opened or for a signature-bound permission macOS granted under an earlier
    /// version: a new signature drops those while System Settings still shows Vortex on.
    func showsRecheckHint(_ permission: Permission) -> Bool {
      if let single, single.permission == permission, single.kind == .lockRefused {
        return true
      }
      guard !isPanel, statuses[permission] == .notGranted else { return false }
      // The pasteboard can't be seen before a relaunch: until one still reads it off, the page says only "Checked
      // after restart" and offers "Restart to check".
      if permission == .pasteboard {
        return checkedAtLaunch.contains(.pasteboard) && rowState(.pasteboard) == .off
      }
      if let single, single.permission == permission, single.kind == .afterUpdate { return true }
      return settingsOpened.contains(permission) || progress.granted[permission] != nil
    }

    /// Whether the window shows at launch: the onboarding isn't done, Vortex is blocked, a page waits for this
    /// relaunch, or an update dropped a permission.
    var showsAtLaunch: Bool {
      !progress.completed || !missingRequired.isEmpty || progress.pendingSingle != nil || !lostInUpdate.isEmpty
    }

    /// What Done's hint says.
    var doneHintText: DoneHint.Line {
      switch (doneHint.notch, doneHint.menuBarIcon, openShortcut) {
      case (.hover?, true, _): .hoverOrIcon
      case let (.hover?, false, shortcut?): .hoverOrShortcut(shortcut)
      case (.hover?, false, nil): .hover
      case (.click?, true, _): .clickOrIcon
      case let (.click?, false, shortcut?): .clickOrShortcut(shortcut)
      case (.click?, false, nil): .click
      // Without a way through the notch, the menu bar icon always shows.
      case (nil, _, _): .icon
      }
    }

    /// The mode QA reports: `window`, `guide`, `single`, `blocked`, or `hidden`.
    var mode: String {
      switch presentation {
      case .hidden: "hidden"
      case .flow: isPanel ? "guide" : (missingRequired.isEmpty ? "window" : "blocked")
      case let .single(single, _):
        isPanel ? "guide" : (single.kind == .blocked ? "blocked" : "single")
      }
    }

    /// The permission the window is about, if it shows one.
    var shownPermission: Permission? {
      switch presentation {
      case .hidden: nil
      case let .single(single, _): single.permission
      case .flow:
        if case let .permission(permission) = page { permission } else { page == .basics ? .notifications : nil }
      }
    }

    /// "Open at login" as Basics shows it: the user's choice until it is applied, on by default for a fresh install
    /// and the real state for one that set it up before; afterwards the real state.
    var openAtLoginShown: Bool {
      guard appliesLoginItem, !progress.loginItemApplied else { return loginItem == .enabled }
      return openAtLoginChoice ?? (loginItemWasSetUp ? loginItem == .enabled : true)
    }
  }

  enum Presentation: Equatable, Sendable {
    case hidden
    /// The onboarding, at `progress.page`.
    case flow(Surface)
    /// One permission's page, outside the onboarding.
    case single(SinglePage, Surface)
  }

  /// Where a shown page is.
  enum Surface: Equatable, Sendable {
    /// The full window.
    case window
    /// The guide panel next to System Settings, for this permission; hidden while another app is in front.
    case panel(Permission, isHidden: Bool)

    var isHidden: Bool {
      if case .panel(_, true) = self { true } else { false }
    }
  }

  struct SinglePage: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
      /// A feature asked for it.
      case request
      /// The first missing required permission after the onboarding is done.
      case blocked
      /// The keyboard lock was refused while the status read granted: no auto-close.
      case lockRefused
      /// Reopened once after the relaunch it started.
      case afterRelaunch
      /// Opened at launch for a permission an update dropped: as a request, with the recheck hint at once.
      case afterUpdate
    }

    var permission: Permission
    var kind: Kind
    /// Shows ✓ and closes after 1.5 s.
    var isClosing = false
  }

  enum RowTag: String, Equatable, Sendable {
    case required, optional
  }

  struct Buttons: Equatable, Sendable {
    var nextVisible: Bool
    var nextEnabled: Bool
    var skipVisible: Bool
  }

  /// What Done's hint names, as the shell sees the settings and screens.
  struct DoneHint: Equatable, Sendable {
    enum Notch: String, Equatable, Sendable {
      case hover, click
    }

    /// How the notch opens Vortex: hovering when Open on hover is on, else clicking when Open on click is on; nil
    /// without either, or without a notch screen.
    var notch: Notch? = .hover
    /// The menu bar icon shows once the onboarding is done.
    var menuBarIcon = true

    /// The sentence Done shows.
    enum Line: Equatable, Sendable {
      case hoverOrIcon, hover, clickOrIcon, click, icon
      case hoverOrShortcut(String), clickOrShortcut(String)
    }
  }

  enum Action: Equatable {
    /// The first statuses were read at launch: show the blocking page, the onboarding if it isn't done, or a page
    /// waiting for this relaunch.
    case launched
    /// Welcome's "Get started".
    case getStartedTapped
    case nextTapped
    case skipTapped
    /// Done's final button: "Start using Vortex" or "Restart and start".
    case finishTapped
    case turnOnTapped(Permission)
    /// "Open System Settings" under the recheck hint.
    case openPaneTapped(Permission)
    /// A row on Done opens its page, which returns to Done.
    case doneRowTapped(Permission)
    /// "Restart now", "Restart to check" and "Restart Vortex".
    case restartTapped
    /// "Later" on a single page that waits for a relaunch.
    case laterTapped
    /// The close button and ⌘W.
    case closeTapped
    /// Esc closes only a single page.
    case escapePressed
    /// The guide panel's "Back".
    case backTapped
    /// «Continue setup».
    case continueSetupTapped
    /// An entry point while Vortex is blocked: a hover shows the window without activating it.
    case blockedEntry(activate: Bool)
    /// Vortex became blocked: on a revoke, a feature turned on, a changed required set, or a lock that ended.
    case blocked
    /// A feature, or the shell, asked for a permission's page.
    case pageRequested(Permission, SinglePage.Kind)
    /// The shell wrote new statuses; `old` is what they were.
    case statusesChanged(old: [Permission: PermissionStatus])
    case appActivated(String)
    case appTerminated(String)
    case loginItemToggled(Bool)
    case loginItemStatusLoaded(LaunchAtLoginStatus)
    case loginItemSetUpLoaded(Bool)
    /// Basics' "Open System Settings", at General › Login Items & Extensions; it gets no panel.
    case openLoginItemsTapped
    case openShortcutLoaded(String?)
    /// The shell read System Settings' own names at launch.
    case systemSettingsNamesLoaded(SystemSettingsNames)
    case navigationUnlocked
    case turnOnUnlocked(Permission)
    case notificationHintExpired
    case guideExpired
    case keepFrontExpired
    case singleCloseElapsed
    case loginItemTick
    /// QA's `onboarding reset`: the onboarding starts over, hidden until something shows it.
    case reset
  }

  @Dependency(\.continuousClock) var clock
  @Dependency(\.hotkeyClient) var hotkeys
  @Dependency(\.launchAtLoginClient) var launchAtLogin
  @Dependency(\.onboardingProgress) var progressClient
  @Dependency(\.onboardingWindow) var window
  @Dependency(\.permissionsClient) var permissions
  @Dependency(\.systemClient) var system

  enum CancelID: Hashable {
    case navigation
    case turnOn(Permission)
    case notificationHint
    case guide
    case keepFront
    case singleClose
    case loginItemTick
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .launched:
        // Any relaunch clears the pending checks; it was this onboarding's one restart.
        state.checkedAtLaunch = state.progress.pendingChecks
        if !state.progress.pendingChecks.isEmpty {
          state.progress.pendingChecks = []
          state.progress.restarted = true
        }
        let pending = state.progress.pendingSingle
        state.progress.pendingSingle = nil
        // After an update, the pages of the permissions macOS dropped: checked once per version, before it is recorded.
        let lost = state.lostInUpdate.filter { $0 != pending }
        state.recordLaunch()
        let saved = save(state)
        // Blocked first: the blocking page opens by itself at launch, before a page waiting for this relaunch.
        if !state.missingRequired.isEmpty { return .merge(saved, showBlocking(activate: true, &state)) }
        if !state.progress.completed { return .merge(saved, showFlow(activate: true, &state)) }
        // Then a page waiting for this relaunch, then the update's pages, one after another.
        state.afterUpdate = lost
        if let pending { return .merge(saved, showSingle(pending, .afterRelaunch, activate: true, &state)) }
        return .merge(saved, showNextAfterUpdate(&state) ?? .none)

      case .getStartedTapped:
        guard state.isFlow, state.page == .welcome, !state.isNavigationLocked, !state.isRelaunching else { return .none }
        return go(to: .basics, &state)

      case .nextTapped:
        guard state.isFlow, !state.isNavigationLocked, !state.isRelaunching, state.buttons.nextEnabled else { return .none }
        return leave(&state)

      case .skipTapped:
        guard state.isFlow, !state.isNavigationLocked, !state.isRelaunching, state.buttons.skipVisible else { return .none }
        return leave(&state)

      case .finishTapped:
        guard state.isFlow, state.page == .done, !state.isNavigationLocked, !state.isRelaunching, state.finishEnabled
        else { return .none }
        if state.finishRestarts {
          // Done shows again after the relaunch, with fresh statuses; the onboarding isn't completed yet.
          state.progress.restarted = true
          return relaunch(&state)
        }
        state.progress.completed = true
        state.progress.returnToDone = false
        return .concatenate(save(state), hide(&state, restoreFront: false))

      case let .turnOnTapped(permission):
        // A checkbox that is on, ↻ included, does nothing.
        guard state.rowState(permission) == .off, !state.turnOnIgnored.contains(permission) else { return .none }
        state.turnOnIgnored.insert(permission)
        state.guideArmed = permission
        if permission == .notifications { state.isNotificationHintVisible = true }
        var effects: [Effect<Action>] = [
          .run { _ in await permissions.request(permission) },
          .run { [ignoreFor = permission == .notifications ? 15 : 2] send in
            try await clock.sleep(for: .seconds(ignoreFor))
            await send(.turnOnUnlocked(permission))
          }
          .cancellable(id: CancelID.turnOn(permission), cancelInFlight: true),
          armGuide(),
        ]
        if permission == .notifications {
          effects.append(
            .run { send in
              try await clock.sleep(for: .seconds(15))
              await send(.notificationHintExpired)
            }
            .cancellable(id: CancelID.notificationHint, cancelInFlight: true)
          )
        }
        // The pasteboard has no prompt: its pane opens, and only a relaunch can tell.
        if permission == .pasteboard {
          state.progress.pendingChecks.insert(.pasteboard)
          effects.append(save(state))
        }
        return .merge(effects)

      case let .openPaneTapped(permission):
        state.guideArmed = permission
        return .merge(.run { _ in await permissions.openSettings(permission) }, armGuide())

      case let .doneRowTapped(permission):
        guard state.isFlow, state.page == .done, !state.isNavigationLocked, !state.isRelaunching,
              state.doneRows.contains(permission)
        else { return .none }
        state.progress.returnToDone = true
        return go(to: .holding(permission), &state)

      case .restartTapped:
        guard !state.isRelaunching else { return .none }
        switch state.presentation {
        case let .single(single, _):
          guard state.waitsForRelaunch || state.showsRestartToCheck(single.permission) else { return .none }
          // The page shows once more after the relaunch it starts.
          state.progress.pendingSingle = single.permission
        case .flow:
          // The same page shows after the relaunch, with fresh statuses; at most once.
          guard state.showsRestartNow || state.shownPermission.map({ state.showsRestartToCheck($0) }) == true else {
            return .none
          }
          state.progress.restarted = true
        case .hidden:
          return .none
        }
        return relaunch(&state)

      case .laterTapped:
        guard state.waitsForRelaunch, !state.isRelaunching else { return .none }
        return closeSingle(&state)

      case .closeTapped:
        switch state.presentation {
        case .hidden: return .none
        case .flow: return hide(&state, restoreFront: false)
        case .single: return closeSingle(&state)
        }

      case .escapePressed:
        guard state.single != nil else { return .none }
        return closeSingle(&state)

      case .backTapped:
        guard state.isPanel else { return .none }
        // Back cancels shrinking until the next request.
        state.guideArmed = nil
        return leavePanel(&state)

      case .continueSetupTapped:
        guard !state.progress.completed else { return .none }
        // While blocked, the page with the missing required permission; otherwise the saved page, replacing a
        // single page. A panel that shows comes forward as a panel.
        if !state.missingRequired.isEmpty { return showBlocking(activate: true, &state) }
        return showFlow(activate: true, &state)

      case let .blockedEntry(activate):
        guard !state.missingRequired.isEmpty else { return .none }
        // A hover leaves a blocking window that already shows as it is.
        if !activate, isShowingBlocking(state) { return .none }
        return showBlocking(activate: activate, &state)

      case .blocked:
        guard !state.missingRequired.isEmpty else { return .none }
        return showBlocking(activate: true, &state)

      case let .pageRequested(permission, kind):
        return pageRequested(permission, kind, &state)

      case let .statusesChanged(old):
        return statusesChanged(old: old, &state)

      case let .appActivated(bundleID):
        return appActivated(bundleID, &state)

      case let .appTerminated(bundleID):
        // Any page that shows, not only the panel: after «Quit & Reopen» Vortex shows the window while System Settings
        // is in front, and the app macOS brings forward in its place would cover it.
        guard bundleID == Self.systemSettingsID, state.isVisible else { return .none }
        state.keepsFront = true
        return .merge(leavePanel(&state), keepFront())

      case let .loginItemToggled(isOn):
        if state.appliesLoginItem, !state.progress.loginItemApplied {
          // Only the choice: it is applied on leaving Basics, so nothing registers while Basics shows.
          state.openAtLoginChoice = isOn
          return .none
        }
        return .run { send in await send(.loginItemStatusLoaded(launchAtLogin.setEnabled(isOn))) }

      case let .loginItemStatusLoaded(status):
        state.loginItem = status
        return .none

      case let .loginItemSetUpLoaded(wasSetUp):
        state.loginItemWasSetUp = wasSetUp
        return .none

      case .openLoginItemsTapped:
        return .run { _ in await launchAtLogin.openSystemSettings() }

      case let .openShortcutLoaded(shortcut):
        state.openShortcut = shortcut
        return .none

      case let .systemSettingsNamesLoaded(names):
        state.settingsNames = names
        return .none

      case .navigationUnlocked:
        state.isNavigationLocked = false
        return .none

      case let .turnOnUnlocked(permission):
        state.turnOnIgnored.remove(permission)
        return .none

      case .notificationHintExpired:
        state.isNotificationHintVisible = false
        return .none

      case .guideExpired:
        state.guideArmed = nil
        return .none

      case .keepFrontExpired:
        state.keepsFront = false
        return .none

      case .singleCloseElapsed:
        // Still granted when the 1.5 s are up; a revoke meanwhile kept the page.
        guard case let .single(single, surface) = state.presentation, single.isClosing, closesOnGrant(single, state)
        else { return .none }
        // Blocked: the next missing required page, in the window, or close.
        if single.kind == .blocked, let next = state.missingRequired.first {
          state.presentation = .single(SinglePage(permission: next, kind: .blocked), .window)
          return surface == .window ? .none : present(state, activate: true)
        }
        return closeSingle(&state)

      case .loginItemTick:
        return .run { send in await send(.loginItemStatusLoaded(launchAtLogin.status())) }

      case .reset:
        state.progress = OnboardingProgress()
        state.settingsOpened = []
        state.checkedAtLaunch = []
        state.turnOnIgnored = []
        state.openAtLoginChoice = nil
        state.isRelaunching = false
        state.afterUpdate = []
        return .concatenate(save(state), hide(&state, restoreFront: false))
      }
    }
  }

  // MARK: - Navigation

  /// Next or Skip: back to Done when the page was opened from it, otherwise the next page.
  private func leave(_ state: inout State) -> Effect<Action> {
    let page = state.page
    var effects: [Effect<Action>] = []
    if page == .basics { effects.append(applyLoginItemChoice(&state)) }
    let next: OnboardingPage
    if state.progress.returnToDone {
      state.progress.returnToDone = false
      next = .done
    } else {
      let pages = state.pages
      next = pages.firstIndex(of: page).map { pages[min($0 + 1, pages.count - 1)] } ?? .done
    }
    effects.append(go(to: next, &state))
    return .merge(effects)
  }

  /// Shows `page` in the window, saving it at once and holding the navigation buttons for 300 ms.
  private func go(to page: OnboardingPage, _ state: inout State) -> Effect<Action> {
    state.progress.page = page.id
    state.isNavigationLocked = true
    state.guideArmed = nil
    state.isNotificationHintVisible = false
    var effects: [Effect<Action>] = [
      save(state),
      .cancel(id: CancelID.guide),
      .cancel(id: CancelID.notificationHint),
      .run { send in
        try await clock.sleep(for: .milliseconds(300))
        await send(.navigationUnlocked)
      }
      .cancellable(id: CancelID.navigation, cancelInFlight: true),
    ]
    // A page change happens in the window: a panel belonged to the page before. The caller brings it forward.
    if state.isFlow, state.isPanel { state.setSurface(.window) }
    effects.append(page == .basics ? loginItemTicks() : .cancel(id: CancelID.loginItemTick))
    if page == .done { effects.append(loadOpenShortcut()) }
    return .merge(effects)
  }

  /// Leaving Basics applies "Open at login" in release builds, once: the user's own choice as they set it,
  /// or, untouched, on for an install that never set it up, which keeps an earlier "off" off.
  private func applyLoginItemChoice(_ state: inout State) -> Effect<Action> {
    guard state.appliesLoginItem, !state.progress.loginItemApplied else { return .none }
    state.progress.loginItemApplied = true
    let choice = state.openAtLoginChoice
    return .run { send in
      if let choice {
        await send(.loginItemStatusLoaded(launchAtLogin.setEnabled(choice)))
      } else {
        await launchAtLogin.enableOnFirstLaunch()
        await send(.loginItemStatusLoaded(launchAtLogin.status()))
      }
    }
  }

  /// Basics re-reads the login item with the statuses, every second while it shows.
  private func loginItemTicks() -> Effect<Action> {
    .run { send in
      await send(.loginItemSetUpLoaded(launchAtLogin.isSetUp()))
      await send(.loginItemTick)
      for await _ in clock.timer(interval: .seconds(1)) {
        await send(.loginItemTick)
      }
    }
    .cancellable(id: CancelID.loginItemTick, cancelInFlight: true)
  }

  private func loadOpenShortcut() -> Effect<Action> {
    .run { send in await send(.openShortcutLoaded(hotkeys.shortcut(.openVortex))) }
  }

  /// System Settings coming to the front within 10 s of a request shrinks the window to the panel.
  private func armGuide() -> Effect<Action> {
    .run { send in
      try await clock.sleep(for: .seconds(10))
      await send(.guideExpired)
    }
    .cancellable(id: CancelID.guide, cancelInFlight: true)
  }

  /// The window stays in front for 1 s after System Settings quit.
  private func keepFront() -> Effect<Action> {
    .run { send in
      try await clock.sleep(for: .seconds(1))
      await send(.keepFrontExpired)
    }
    .cancellable(id: CancelID.keepFront, cancelInFlight: true)
  }

  private func save(_ state: State) -> Effect<Action> {
    // Synchronous: a forced quit right after a page change still resumes there.
    progressClient.save(state.progress)
    return .none
  }

  /// Saves, then relaunches; until the process is gone, no other navigation or finish is taken.
  private func relaunch(_ state: inout State) -> Effect<Action> {
    state.isRelaunching = true
    return .concatenate(save(state), .run { _ in await system.relaunch() })
  }

  // MARK: - Showing and hiding

  /// The onboarding at its page, replacing a single page.
  private func showFlow(activate: Bool, _ state: inout State) -> Effect<Action> {
    let wasHidden = !state.isVisible
    if !state.isFlow { state.presentation = .flow(.window) }
    var effects: [Effect<Action>] = [bringForward(activate: activate, &state)]
    if wasHidden {
      effects.append(.run { _ in await permissions.setFrequentChecks(true) })
      if state.page == .basics { effects.append(loginItemTicks()) }
      if state.page == .done { effects.append(loadOpenShortcut()) }
    }
    return .merge(effects)
  }

  private func showSingle(
    _ permission: Permission,
    _ kind: SinglePage.Kind,
    activate: Bool,
    _ state: inout State
  ) -> Effect<Action> {
    let wasHidden = !state.isVisible
    // A request switches the page to the latest permission; a panel for another one closes.
    var surface = Surface.window
    if let current = state.surface, state.guided == permission { surface = current }
    state.guideArmed = nil
    var page = SinglePage(permission: permission, kind: kind)
    // Reopened after its relaunch and on already: ✓, then close.
    if kind == .afterRelaunch, closesOnGrant(page, state) { page.isClosing = true }
    state.presentation = .single(page, surface)
    var effects: [Effect<Action>] = [bringForward(activate: activate, &state)]
    if wasHidden { effects.append(.run { _ in await permissions.setFrequentChecks(true) }) }
    if page.isClosing { effects.append(closeSingleLater()) }
    effects.append(.cancel(id: CancelID.loginItemTick))
    return .merge(effects)
  }

  /// Blocked: before completion the onboarding jumps to the first page with a missing required permission;
  /// after it, the single page of that permission, tagged Required, with Close only.
  private func showBlocking(activate: Bool, _ state: inout State) -> Effect<Action> {
    guard let first = state.missingRequired.first else { return .none }
    if !state.progress.completed {
      var effects: [Effect<Action>] = []
      let blockedPage = state.pages.first { page in state.rows(on: page).contains(where: state.isRequiredMissing) }
        ?? .holding(first)
      if state.page != blockedPage {
        state.progress.returnToDone = false
        effects.append(go(to: blockedPage, &state))
      }
      effects.append(showFlow(activate: activate, &state))
      return .merge(effects)
    }
    if let single = state.single, single.kind == .blocked, single.permission == first {
      return bringForward(activate: activate, &state)
    }
    return showSingle(first, .blocked, activate: activate, &state)
  }

  /// Whether the blocking page is on screen: a panel that stepped aside isn't.
  private func isShowingBlocking(_ state: State) -> Bool {
    switch state.presentation {
    case .hidden: false
    case let .flow(surface): !state.progress.completed && !surface.isHidden
    case let .single(single, surface): single.kind == .blocked && !surface.isHidden
    }
  }

  /// Every path that brings the onboarding forward goes through here: a panel that shows comes
  /// forward as a panel; one that stepped aside because another app came to the front turns back into the window, as
  /// the System Settings window it stood next to is behind that app.
  private func bringForward(activate: Bool, _ state: inout State) -> Effect<Action> {
    if state.isPanelHidden { state.setSurface(.window) }
    return present(state, activate: activate)
  }

  private func present(_ state: State, activate: Bool) -> Effect<Action> {
    let mode: OnboardingWindowMode = switch state.surface {
    case .panel(_, isHidden: true)?: .panelHidden
    case .panel?: .panel
    case .window?, nil: .window
    }
    return .run { _ in await window.present(mode, activate) }
  }

  private func hide(_ state: inout State, restoreFront: Bool) -> Effect<Action> {
    state.presentation = .hidden
    state.guideArmed = nil
    state.keepsFront = false
    state.lastApp = nil
    state.isNotificationHintVisible = false
    return .merge(
      .cancel(id: CancelID.singleClose),
      .cancel(id: CancelID.loginItemTick),
      .cancel(id: CancelID.guide),
      .cancel(id: CancelID.keepFront),
      .run { _ in
        await window.hide(restoreFront)
        await permissions.setFrequentChecks(false)
      }
    )
  }

  /// A single page closes; after an update, the next page whose permission still reads off shows instead, unless Vortex
  /// is blocked.
  private func closeSingle(_ state: inout State) -> Effect<Action> {
    guard state.missingRequired.isEmpty, let next = showNextAfterUpdate(&state) else {
      return hide(&state, restoreFront: true)
    }
    state.isNotificationHintVisible = false
    return .merge(.cancel(id: CancelID.singleClose), .cancel(id: CancelID.notificationHint), next)
  }

  /// The single page of the next permission the update dropped that still reads `notGranted`; nil when none is left.
  private func showNextAfterUpdate(_ state: inout State) -> Effect<Action>? {
    while !state.afterUpdate.isEmpty {
      let next = state.afterUpdate.removeFirst()
      if state.statuses[next] == .notGranted { return showSingle(next, .afterUpdate, activate: true, &state) }
    }
    return nil
  }

  private func closeSingleLater() -> Effect<Action> {
    .run { send in
      try await clock.sleep(for: .milliseconds(1_500))
      await send(.singleCloseElapsed)
    }
    .cancellable(id: CancelID.singleClose, cancelInFlight: true)
  }

  /// A single page shows ✓ and closes on a grant: `granted`, or `notNeeded`, which is how the
  /// pasteboard reads once macOS allows it; for the blocking page `grantedAfterRestart` too, which counts as on for
  /// blocking. Never the page the refused lock opened.
  private func closesOnGrant(_ single: SinglePage, _ state: State) -> Bool {
    switch state.statuses[single.permission] {
    case .granted?, .notNeeded?: single.kind != .lockRefused
    case .grantedAfterRestart?: single.kind == .blocked
    case .notGranted?, nil: false
    }
  }

  // MARK: - Requests, statuses and System Settings

  private func pageRequested(_ permission: Permission, _ kind: SinglePage.Kind, _ state: inout State) -> Effect<Action> {
    // While blocked every request shows the blocking page, whatever was asked for.
    if !state.missingRequired.isEmpty { return showBlocking(activate: true, &state) }
    switch state.presentation {
    case .flow:
      // The onboarding comes to the front at its page.
      return bringForward(activate: true, &state)
    case .hidden, .single:
      // Closed before completion: a single page, and the saved page stays as it was.
      return showSingle(permission, kind, activate: true, &state)
    }
  }

  private func statusesChanged(old: [Permission: PermissionStatus], _ state: inout State) -> Effect<Action> {
    var effects: [Effect<Action>] = []
    for permission in Permission.allCases where old[permission] != state.statuses[permission] {
      // A changed status lets "Turn on" take clicks again and ends the notifications hint.
      if state.turnOnIgnored.remove(permission) != nil {
        effects.append(.cancel(id: CancelID.turnOn(permission)))
      }
      if permission == .notifications, state.isNotificationHintVisible {
        state.isNotificationHintVisible = false
        effects.append(.cancel(id: CancelID.notificationHint))
      }
    }
    // The panel turns back into the window once its permission is on.
    if let guided = state.guided, state.statuses[guided]?.isOn == true || state.statuses[guided] == .notNeeded {
      effects.append(leavePanel(&state))
    }
    // A single page shows ✓ and closes after 1.5 s on a grant; one that waits for a relaunch offers "Restart Vortex"
    // and "Later" instead. Revoked within those 1.5 s, the page stays, with its checkbox off.
    if case .single(var single, let surface) = state.presentation {
      let closes = closesOnGrant(single, state)
      if closes != single.isClosing {
        single.isClosing = closes
        state.presentation = .single(single, surface)
        effects.append(closes ? closeSingleLater() : .cancel(id: CancelID.singleClose))
      }
    }
    if state.isVisible, state.isFlow, state.page == .basics {
      effects.append(.send(.loginItemTick))
    }
    // What macOS grants is kept with this version. The launch's first read waits for `launched`, which checks first
    // what the update dropped.
    if !old.isEmpty, state.recordGrants() { effects.append(save(state)) }
    return .merge(effects)
  }

  private func appActivated(_ bundleID: String, _ state: inout State) -> Effect<Action> {
    guard state.isVisible else { return .none }
    if bundleID == OnboardingFeature.systemSettingsID {
      if let armed = state.guideArmed, !state.isPanel, armed == state.shownPermission {
        // Once per request; the hint about the notification gives way to System Settings.
        state.guideArmed = nil
        state.setSurface(.panel(armed, isHidden: false))
        state.settingsOpened.insert(armed)
        state.isNotificationHintVisible = false
        return .merge(.cancel(id: CancelID.guide), present(state, activate: false))
      }
      if let guided = state.guided {
        // Placed again on each activation, and back if it stepped aside.
        state.setSurface(.panel(guided, isHidden: false))
        return present(state, activate: false)
      }
      return .none
    }
    let isVortex = bundleID == state.ownBundleID
    if !isVortex {
      // macOS reports the app it brings forward in System Settings' place just before the quit, or else as the first
      // after it: within the second the window goes back over that app, never over one the user switches to.
      let isFromBefore = state.lastApp == nil || state.lastApp == bundleID
      state.lastApp = bundleID
      if state.keepsFront, isFromBefore, !state.isPanel { return present(state, activate: true) }
    }
    guard let guided = state.guided else { return .none }
    if isVortex == state.isPanelHidden {
      state.setSurface(.panel(guided, isHidden: !isVortex))
      return present(state, activate: false)
    }
    return .none
  }

  /// The full window, in front: a panel that shows or stepped aside turns back into it.
  private func leavePanel(_ state: inout State) -> Effect<Action> {
    state.setSurface(.window)
    return present(state, activate: true)
  }
}
