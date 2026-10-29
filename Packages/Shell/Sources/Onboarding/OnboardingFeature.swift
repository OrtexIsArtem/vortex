import ComposableArchitecture
import Foundation
import VortexCore
import VortexPlatform

/// The first-run onboarding and the single permission page (S6–S21, S24, S41, S49–S55, S65–S81). The shell owns it:
/// it keeps `catalog`, `steps` and `doneHint` current, hands it the entry points while Vortex is blocked, and the
/// requests features make through `PermissionPage`.
@Reducer
struct OnboardingFeature {
  /// System Settings' bundle id: the guide panel sits next to its window (S15).
  static let systemSettingsID = "com.apple.systempreferences"

  @ObservableState
  struct State: Equatable {
    /// Saved in DataFolder/onboarding.json on every change (S21, S71).
    var progress = OnboardingProgress()
    /// What the enabled features and the shell need, and what is required; the shell keeps it current.
    var catalog = PermissionCatalog(features: [], required: [])
    /// Enabled features that bring their own step (S17), in sidebar order.
    var steps: [FeatureID] = []
    /// Every feature with a step, on or off, in sidebar order: where a step's page sits in the order (S71).
    var stepOrder: [FeatureID] = []
    @SharedReader(.permissionStatuses) var statuses
    @SharedReader(.onboardingStepsDone) var stepsDone
    /// Whether the window shows, what, and as the full window or the guide panel.
    var presentation: Presentation = .hidden
    /// A "Turn on" click armed the panel: System Settings coming to the front within 10 s shrinks the window (S73).
    var guideArmed: Permission?
    /// System Settings came to the front after a request from these pages (S16, S59).
    var settingsOpened: Set<Permission> = []
    /// Permissions whose check waited for this launch's relaunch (S68): the pasteboard's page gives S59's hint only
    /// once that relaunch still reads it off, as nothing before it can tell (S16).
    var checkedAtLaunch: Set<Permission> = []
    /// "Click Allow in the notification…" under the notifications row, for 15 s or until the status changes (S13).
    var isNotificationHintVisible = false
    /// "Turn on" ignores more clicks until the status changes, or for 2 s (15 s for notifications) (S70).
    var turnOnIgnored: Set<Permission> = []
    /// Navigation buttons ignore input for 300 ms after a page change (S70).
    var isNavigationLocked = false
    /// A relaunch was asked for: until the process is gone, no other navigation or finish is taken (S18).
    var isRelaunching = false
    var loginItem: LaunchAtLoginStatus = .disabled
    /// "Open at login" as the user set it on Basics, applied when they leave it (S74); nil until they touch the switch.
    var openAtLoginChoice: Bool?
    /// Vortex set the login item up before, as every release build before stage 7 did: the switch starts from the
    /// real state, not from "on".
    var loginItemWasSetUp = false
    /// Release builds, and QA runs with release behavior, apply the login item choice (S13, S74).
    var appliesLoginItem = false
    /// Vortex's own bundle id: Vortex in front keeps the panel showing (S63).
    var ownBundleID = Bundle.main.bundleIdentifier ?? ""
    /// What Done's hint names, from the settings and screens (S75).
    var doneHint = DoneHint()
    /// The "Open Vortex" shortcut, read when Done shows; nil while none is set.
    var openShortcut: String?

    init(progress: OnboardingProgress = OnboardingProgress()) {
      self.progress = progress
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
    /// The panel stepped aside while another app is in front (S63).
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

    /// The required permissions that read `notGranted`, in the catalog's order (S9, S66).
    var missingRequired: [Permission] { catalog.missingRequired(statuses) }

    /// Every page of this onboarding, in order. A permission macOS doesn't ask for here has no page (S1).
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

    /// The saved page; one that no longer exists resumes at the next page in order, else Done (S71). A page id this
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

    /// One row per needed permission on Done (S18).
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

    /// A required permission that reads off shows "Required" (S19, S41, S53).
    func isRequiredMissing(_ permission: Permission) -> Bool {
      catalog.entry(for: permission)?.isRequired == true && statuses[permission] == .notGranted
    }

    /// The tag beside a row's title: "Required" for a required permission that is off, wherever it shows; "Optional"
    /// for one that is off and can be skipped, on the onboarding's pages, where Skip is there for it (S19). Nothing
    /// before the first read, or once it is on.
    func rowTag(_ permission: Permission) -> RowTag? {
      if isRequiredMissing(permission) { return .required }
      guard isFlow, rowState(permission) == .off, catalog.entry(for: permission)?.isRequired == false else { return nil }
      return .optional
    }

    /// Next and Skip on the page shown (S19, S72, S78).
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

    /// Done's final button reads "Restart and start" while a grant waits for a relaunch, once per onboarding (S18, S68).
    var finishRestarts: Bool {
      guard !progress.restarted else { return false }
      return !progress.pendingChecks.isEmpty || doneRows.contains { statuses[$0] == .grantedAfterRestart }
    }

    /// Done's final button waits for every required permission (S53).
    var finishEnabled: Bool {
      statusesRead && !doneRows.contains(where: isRequiredMissing)
    }

    /// The quiet "Restart now" link (S20): a permission on the page works only after a relaunch, and Vortex hasn't
    /// relaunched during this onboarding yet (S68).
    var showsRestartNow: Bool {
      guard isFlow, !progress.restarted else { return false }
      return rows(on: page).contains { statuses[$0] == .grantedAfterRestart }
    }

    /// "Restart to check" under the pasteboard once its pane was opened (S16, S68): on a single page always, in the
    /// onboarding only before its one restart.
    func showsRestartToCheck(_ permission: Permission) -> Bool {
      guard permission == .pasteboard, progress.pendingChecks.contains(.pasteboard) else { return false }
      return single != nil || !progress.restarted
    }

    /// A single page whose permission waits for a relaunch: ✓, "Restart Vortex" and "Later" (S24, S40).
    var waitsForRelaunch: Bool {
      guard let single else { return false }
      return statuses[single.permission] == .grantedAfterRestart
    }

    /// "Already on in System Settings? Turn it off and on again." (S59), and S55's line on a page the lock opened.
    func showsRecheckHint(_ permission: Permission) -> Bool {
      if let single, single.permission == permission, single.kind == .lockRefused {
        return true
      }
      guard !isPanel, statuses[permission] == .notGranted else { return false }
      // The pasteboard can't be seen before a relaunch: until one still reads it off, the page says only "Checked
      // after restart" and offers "Restart to check" (S16, S68).
      if permission == .pasteboard {
        return checkedAtLaunch.contains(.pasteboard) && rowState(.pasteboard) == .off
      }
      return settingsOpened.contains(permission)
    }

    /// Whether the window shows at launch: the onboarding isn't done, Vortex is blocked, or a page waits for this
    /// relaunch (S7, S41, S50).
    var showsAtLaunch: Bool {
      !progress.completed || !missingRequired.isEmpty || progress.pendingSingle != nil
    }

    /// What Done's hint says (S18, S75).
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
    /// and the real state for one that set it up before (S13, S74); afterwards the real state.
    var openAtLoginShown: Bool {
      guard appliesLoginItem, !progress.loginItemApplied else { return loginItem == .enabled }
      return openAtLoginChoice ?? (loginItemWasSetUp ? loginItem == .enabled : true)
    }
  }

  enum Presentation: Equatable, Sendable {
    case hidden
    /// The onboarding, at `progress.page`.
    case flow(Surface)
    /// One permission's page (S24), outside the onboarding.
    case single(SinglePage, Surface)
  }

  /// Where a shown page is.
  enum Surface: Equatable, Sendable {
    /// The full window.
    case window
    /// The guide panel next to System Settings, for this permission (S15); hidden while another app is in front (S63).
    case panel(Permission, isHidden: Bool)

    var isHidden: Bool {
      if case .panel(_, true) = self { true } else { false }
    }
  }

  struct SinglePage: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
      /// A feature asked for it (S24).
      case request
      /// The first missing required permission after the onboarding is done (S41).
      case blocked
      /// The keyboard lock was refused while the status read granted: no auto-close (S55).
      case lockRefused
      /// Reopened once after the relaunch it started (S50).
      case afterRelaunch
    }

    var permission: Permission
    var kind: Kind
    /// Shows ✓ and closes after 1.5 s (S24, S41).
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

  /// What Done's hint names (S75), as the shell sees the settings and screens.
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
    /// waiting for this relaunch (S7, S41, S50, S64).
    case launched
    /// Welcome's "Get started".
    case getStartedTapped
    case nextTapped
    case skipTapped
    /// Done's final button: "Start using Vortex" or "Restart and start" (S18).
    case finishTapped
    case turnOnTapped(Permission)
    /// The pane button of S55 and S59.
    case openPaneTapped(Permission)
    /// A row on Done opens its page, which returns to Done (S18, S77).
    case doneRowTapped(Permission)
    /// "Restart now", "Restart to check" and "Restart Vortex" (S16, S20, S24, S50).
    case restartTapped
    /// "Later" on a single page that waits for a relaunch.
    case laterTapped
    /// The close button and ⌘W (S10, S60).
    case closeTapped
    /// Esc closes only a single page (S60, S79).
    case escapePressed
    /// The guide panel's "Back" (S15).
    case backTapped
    /// «Продовжити налаштування» (S69, S80).
    case continueSetupTapped
    /// An entry point while Vortex is blocked (S9, S46): a hover shows the window without activating it.
    case blockedEntry(activate: Bool)
    /// Vortex became blocked: on a revoke, a feature turned on, a changed required set, or a lock that ended (S41, S65).
    case blocked
    /// A feature, or the shell, asked for a permission's page (S24).
    case pageRequested(Permission, SinglePage.Kind)
    /// The shell wrote new statuses; `old` is what they were.
    case statusesChanged(old: [Permission: PermissionStatus])
    case appActivated(String)
    case appTerminated(String)
    case loginItemToggled(Bool)
    case loginItemStatusLoaded(LaunchAtLoginStatus)
    case loginItemSetUpLoaded(Bool)
    /// Basics' button for System Settings › Login Items; it gets no panel (S73).
    case openLoginItemsTapped
    case openShortcutLoaded(String?)
    case navigationUnlocked
    case turnOnUnlocked(Permission)
    case notificationHintExpired
    case guideExpired
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
    case singleClose
    case loginItemTick
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .launched:
        // Any relaunch clears the pending checks; it was this onboarding's one restart (S68).
        state.checkedAtLaunch = state.progress.pendingChecks
        if !state.progress.pendingChecks.isEmpty {
          state.progress.pendingChecks = []
          state.progress.restarted = true
        }
        let pending = state.progress.pendingSingle
        state.progress.pendingSingle = nil
        let saved = save(state)
        // Blocked first: the blocking page opens by itself at launch, before a page waiting for this relaunch (S41).
        if !state.missingRequired.isEmpty { return .merge(saved, showBlocking(activate: true, &state)) }
        if !state.progress.completed { return .merge(saved, showFlow(activate: true, &state)) }
        guard let pending else { return saved }
        return .merge(saved, showSingle(pending, .afterRelaunch, activate: true, &state))

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
          // Done shows again after the relaunch, with fresh statuses; the onboarding isn't completed yet (S18, S68).
          state.progress.restarted = true
          return relaunch(&state)
        }
        state.progress.completed = true
        state.progress.returnToDone = false
        return .concatenate(save(state), hide(&state, restoreFront: false))

      case let .turnOnTapped(permission):
        // A checkbox that is on, ↻ included, does nothing (S2).
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
        // The pasteboard has no prompt: its pane opens, and only a relaunch can tell (S16, S68).
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
          // The page shows once more after the relaunch it starts (S50).
          state.progress.pendingSingle = single.permission
        case .flow:
          // The same page shows after the relaunch, with fresh statuses (S20); at most once (S68).
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
        return hide(&state, restoreFront: true)

      case .closeTapped:
        switch state.presentation {
        case .hidden: return .none
        case .flow: return hide(&state, restoreFront: false)
        case .single: return hide(&state, restoreFront: true)
        }

      case .escapePressed:
        guard state.single != nil else { return .none }
        return hide(&state, restoreFront: true)

      case .backTapped:
        guard state.isPanel else { return .none }
        // Back cancels shrinking until the next request (S73).
        state.guideArmed = nil
        return leavePanel(&state)

      case .continueSetupTapped:
        guard !state.progress.completed else { return .none }
        // While blocked, the page with the missing required permission (S65); otherwise the saved page, replacing a
        // single page (S80). A panel that shows comes forward as a panel (S69).
        if !state.missingRequired.isEmpty { return showBlocking(activate: true, &state) }
        return showFlow(activate: true, &state)

      case let .blockedEntry(activate):
        guard !state.missingRequired.isEmpty else { return .none }
        // A hover leaves a blocking window that already shows as it is (S46).
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
        guard bundleID == Self.systemSettingsID, state.isPanel else { return .none }
        return leavePanel(&state)

      case let .loginItemToggled(isOn):
        if state.appliesLoginItem, !state.progress.loginItemApplied {
          // Only the choice: it is applied on leaving Basics, so nothing registers while Basics shows (S74).
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

      case .singleCloseElapsed:
        // Still granted when the 1.5 s are up; a revoke meanwhile kept the page (S24, S26).
        guard case let .single(single, surface) = state.presentation, single.isClosing, closesOnGrant(single, state)
        else { return .none }
        // Blocked: the next missing required page, in the window, or close (S41).
        if single.kind == .blocked, let next = state.missingRequired.first {
          state.presentation = .single(SinglePage(permission: next, kind: .blocked), .window)
          return surface == .window ? .none : present(state, activate: true)
        }
        return hide(&state, restoreFront: true)

      case .loginItemTick:
        return .run { send in await send(.loginItemStatusLoaded(launchAtLogin.status())) }

      case .reset:
        state.progress = OnboardingProgress()
        state.settingsOpened = []
        state.checkedAtLaunch = []
        state.turnOnIgnored = []
        state.openAtLoginChoice = nil
        state.isRelaunching = false
        return .concatenate(save(state), hide(&state, restoreFront: false))
      }
    }
  }

  // MARK: - Navigation

  /// Next or Skip: back to Done when the page was opened from it, otherwise the next page (S18, S19).
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

  /// Shows `page` in the window, saving it at once (S21) and holding the navigation buttons for 300 ms (S70).
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

  /// Leaving Basics applies "Open at login" in release builds, once (S13, S74): the user's own choice as they set it,
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

  /// Basics re-reads the login item with the statuses, every second while it shows (S81).
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

  /// System Settings coming to the front within 10 s of a request shrinks the window to the panel (S73).
  private func armGuide() -> Effect<Action> {
    .run { send in
      try await clock.sleep(for: .seconds(10))
      await send(.guideExpired)
    }
    .cancellable(id: CancelID.guide, cancelInFlight: true)
  }

  private func save(_ state: State) -> Effect<Action> {
    // Synchronous: a forced quit right after a page change still resumes there (S71).
    progressClient.save(state.progress)
    return .none
  }

  /// Saves, then relaunches; until the process is gone, no other navigation or finish is taken (S18).
  private func relaunch(_ state: inout State) -> Effect<Action> {
    state.isRelaunching = true
    return .concatenate(save(state), .run { _ in await system.relaunch() })
  }

  // MARK: - Showing and hiding

  /// The onboarding at its page, replacing a single page (S80).
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
    // A request switches the page to the latest permission; a panel for another one closes (S51).
    var surface = Surface.window
    if let current = state.surface, state.guided == permission { surface = current }
    state.guideArmed = nil
    var page = SinglePage(permission: permission, kind: kind)
    // Reopened after its relaunch and on already: ✓, then close (S50).
    if kind == .afterRelaunch, closesOnGrant(page, state) { page.isClosing = true }
    state.presentation = .single(page, surface)
    var effects: [Effect<Action>] = [bringForward(activate: activate, &state)]
    if wasHidden { effects.append(.run { _ in await permissions.setFrequentChecks(true) }) }
    if page.isClosing { effects.append(closeSingleLater()) }
    effects.append(.cancel(id: CancelID.loginItemTick))
    return .merge(effects)
  }

  /// Blocked: before completion the onboarding jumps to the first page with a missing required permission (S65);
  /// after it, the single page of that permission, tagged Required, with Close only (S41).
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

  /// Every path that brings the onboarding forward goes through here (S9, S11, S52, S69): a panel that shows comes
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
    state.isNotificationHintVisible = false
    return .merge(
      .cancel(id: CancelID.singleClose),
      .cancel(id: CancelID.loginItemTick),
      .cancel(id: CancelID.guide),
      .run { _ in
        await window.hide(restoreFront)
        await permissions.setFrequentChecks(false)
      }
    )
  }

  private func closeSingleLater() -> Effect<Action> {
    .run { send in
      try await clock.sleep(for: .milliseconds(1_500))
      await send(.singleCloseElapsed)
    }
    .cancellable(id: CancelID.singleClose, cancelInFlight: true)
  }

  /// A single page shows ✓ and closes on a grant (S24, S41, S50): `granted`, or `notNeeded`, which is how the
  /// pasteboard reads once macOS allows it; for the blocking page `grantedAfterRestart` too, which counts as on for
  /// blocking (S82). Never the page the refused lock opened (S55).
  private func closesOnGrant(_ single: SinglePage, _ state: State) -> Bool {
    switch state.statuses[single.permission] {
    case .granted?, .notNeeded?: single.kind != .lockRefused
    case .grantedAfterRestart?: single.kind == .blocked
    case .notGranted?, nil: false
    }
  }

  // MARK: - Requests, statuses and System Settings

  private func pageRequested(_ permission: Permission, _ kind: SinglePage.Kind, _ state: inout State) -> Effect<Action> {
    // While blocked every request shows the blocking page, whatever was asked for (S43).
    if !state.missingRequired.isEmpty { return showBlocking(activate: true, &state) }
    switch state.presentation {
    case .flow:
      // The onboarding comes to the front at its page (S11, S52).
      return bringForward(activate: true, &state)
    case .hidden, .single:
      // Closed before completion: a single page, and the saved page stays as it was (S52).
      return showSingle(permission, kind, activate: true, &state)
    }
  }

  private func statusesChanged(old: [Permission: PermissionStatus], _ state: inout State) -> Effect<Action> {
    var effects: [Effect<Action>] = []
    for permission in Permission.allCases where old[permission] != state.statuses[permission] {
      // A changed status lets "Turn on" take clicks again and ends the notifications hint (S13, S70).
      if state.turnOnIgnored.remove(permission) != nil {
        effects.append(.cancel(id: CancelID.turnOn(permission)))
      }
      if permission == .notifications, state.isNotificationHintVisible {
        state.isNotificationHintVisible = false
        effects.append(.cancel(id: CancelID.notificationHint))
      }
    }
    // The panel turns back into the window once its permission is on (S15).
    if let guided = state.guided, state.statuses[guided]?.isOn == true || state.statuses[guided] == .notNeeded {
      effects.append(leavePanel(&state))
    }
    // A single page shows ✓ and closes after 1.5 s on a grant; one that waits for a relaunch offers "Restart Vortex"
    // and "Later" instead. Revoked within those 1.5 s, the page stays, with its checkbox off (S2, S26).
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
    return .merge(effects)
  }

  private func appActivated(_ bundleID: String, _ state: inout State) -> Effect<Action> {
    guard state.isVisible else { return .none }
    if bundleID == OnboardingFeature.systemSettingsID {
      if let armed = state.guideArmed, !state.isPanel, armed == state.shownPermission {
        // Once per request (S73); the hint about the notification gives way to System Settings.
        state.guideArmed = nil
        state.setSurface(.panel(armed, isHidden: false))
        state.settingsOpened.insert(armed)
        state.isNotificationHintVisible = false
        return .merge(.cancel(id: CancelID.guide), present(state, activate: false))
      }
      if let guided = state.guided {
        // Placed again on each activation, and back if it stepped aside (S63, S73).
        state.setSurface(.panel(guided, isHidden: false))
        return present(state, activate: false)
      }
      return .none
    }
    guard let guided = state.guided else { return .none }
    let isVortex = bundleID == state.ownBundleID
    if isVortex == state.isPanelHidden {
      state.setSurface(.panel(guided, isHidden: !isVortex))
      return present(state, activate: false)
    }
    return .none
  }

  /// The panel turns back into the full window, in front (S15, S61).
  private func leavePanel(_ state: inout State) -> Effect<Action> {
    state.setSurface(.window)
    return present(state, activate: true)
  }
}
