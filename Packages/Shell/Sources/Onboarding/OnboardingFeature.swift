import ComposableArchitecture
import Foundation
import VortexCore
import VortexPlatform

/// The first-run onboarding and the single permission page (S6–S21, S24, S41, S49–S55, S65–S81). The shell owns it:
/// it keeps `catalog` and `steps` current, hands it the entry points while Vortex is blocked, and the requests features
/// make through `PermissionPage`.
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
    @SharedReader(.permissionStatuses) var statuses
    @SharedReader(.onboardingStepsDone) var stepsDone
    /// Whether the window shows, and what.
    var presentation: Presentation = .hidden
    /// The window is the small guide panel next to System Settings (S15).
    var isPanel = false
    /// The panel steps aside while an app other than System Settings or Vortex is in front (S63).
    var isPanelHidden = false
    /// The permission the guide panel shows.
    var guided: Permission?
    /// A "Turn on" click armed the panel: System Settings coming to the front within 10 s shrinks the window (S73).
    var guideArmed: Permission?
    /// System Settings came to the front after a request from these pages (S16, S59).
    var settingsOpened: Set<Permission> = []
    /// "Click Allow in the notification…" under the notifications row, for 15 s or until the status changes (S13).
    var isNotificationHintVisible = false
    /// "Turn on" ignores more clicks until the status changes, or for 2 s (15 s for notifications) (S70).
    var turnOnIgnored: Set<Permission> = []
    /// Navigation buttons ignore input for 300 ms after a page change (S70).
    var isNavigationLocked = false
    var loginItem: LaunchAtLoginStatus = .disabled
    /// "Open at login" as the user chose it on Basics, applied when they leave it (S74).
    var openAtLoginChoice = true
    /// Release builds, and QA runs with release behavior, apply the login item choice (S13, S74).
    var appliesLoginItem = false
    /// Vortex's own bundle id: Vortex in front keeps the panel showing (S63).
    var ownBundleID = Bundle.main.bundleIdentifier ?? ""
    /// What Done's hint names (S75).
    var doneHint = DoneHint()

    init(progress: OnboardingProgress = OnboardingProgress()) {
      self.progress = progress
    }

    var isVisible: Bool { presentation != .hidden }
    var isCompleted: Bool { progress.completed }
    var statusesRead: Bool { !statuses.isEmpty }

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

    /// The saved page; one that no longer exists resumes at the next page in order, else Done (S71).
    var page: OnboardingPage {
      let pages = pages
      guard let saved = OnboardingPage(id: progress.page) else { return .welcome }
      if pages.contains(saved) { return saved }
      return pages.first { $0.rank > saved.rank } ?? .done
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
      guard !progress.restarted else { return false }
      return rows(on: page).contains { statuses[$0] == .grantedAfterRestart }
    }

    /// "Already on in System Settings? Turn it off and on again." (S59), and S55's line on a page the lock opened.
    func showsRecheckHint(_ permission: Permission) -> Bool {
      if case let .single(single) = presentation, single.permission == permission, single.kind == .lockRefused {
        return true
      }
      return settingsOpened.contains(permission) && statuses[permission] == .notGranted && !isPanel
    }

    /// The mode QA reports: `window`, `guide`, `single`, `blocked`, or `hidden`.
    var mode: String {
      switch presentation {
      case .hidden: "hidden"
      case .flow: isPanel ? "guide" : (missingRequired.isEmpty ? "window" : "blocked")
      case let .single(single):
        isPanel ? "guide" : (single.kind == .blocked ? "blocked" : "single")
      }
    }

    /// The permission the window is about, if it shows one.
    var shownPermission: Permission? {
      switch presentation {
      case .hidden: nil
      case let .single(single): single.permission
      case .flow:
        if case let .permission(permission) = page { permission } else { page == .basics ? .notifications : nil }
      }
    }
  }

  enum Presentation: Equatable, Sendable {
    case hidden
    /// The onboarding, at `progress.page`.
    case flow
    /// One permission's page (S24), outside the onboarding.
    case single(SinglePage)
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

  struct Buttons: Equatable, Sendable {
    var nextVisible: Bool
    var nextEnabled: Bool
    var skipVisible: Bool
  }

  /// What Done's hint names (S75): hovering over the notch only when Open on hover is on and a notch screen is
  /// connected; the menu bar icon when it shows, otherwise the "Open Vortex" shortcut if one is set.
  struct DoneHint: Equatable, Sendable {
    var hoverNotch = true
    var menuBarIcon = true
    var shortcut: String?
  }

  enum Action: Equatable {
    /// The first statuses were read at launch: show the onboarding if it isn't done, or a page waiting for this
    /// relaunch (S7, S50, S64).
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
    /// Vortex became blocked, at launch or on a revoke (S41, S65).
    case blocked
    /// A feature, or the shell, asked for a permission's page (S24).
    case pageRequested(Permission, SinglePage.Kind)
    /// The shell wrote new statuses; `old` is what they were.
    case statusesChanged(old: [Permission: PermissionStatus])
    case appActivated(String)
    case appTerminated(String)
    case loginItemToggled(Bool)
    case loginItemStatusLoaded(LaunchAtLoginStatus)
    /// Basics' button for System Settings › Login Items; it gets no panel (S73).
    case openLoginItemsTapped
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
        var progress = state.progress
        // Any relaunch clears the pending checks; it was this onboarding's one restart (S68).
        if !progress.pendingChecks.isEmpty {
          progress.pendingChecks = []
          progress.restarted = true
        }
        if progress.completed, let pending = progress.pendingSingle {
          progress.pendingSingle = nil
          state.progress = progress
          return .merge(save(state), showSingle(pending, .afterRelaunch, activate: true, &state))
        }
        progress.pendingSingle = nil
        state.progress = progress
        if !state.missingRequired.isEmpty {
          return .merge(save(state), showBlocking(activate: true, &state))
        }
        guard !progress.completed else { return save(state) }
        return .merge(save(state), showFlow(activate: true, &state))

      case .getStartedTapped:
        guard state.page == .welcome, !state.isNavigationLocked else { return .none }
        return go(to: .basics, &state)

      case .nextTapped:
        guard !state.isNavigationLocked, state.buttons.nextEnabled else { return .none }
        return leave(&state)

      case .skipTapped:
        guard !state.isNavigationLocked, state.buttons.skipVisible else { return .none }
        return leave(&state)

      case .finishTapped:
        guard state.page == .done, !state.isNavigationLocked, state.finishEnabled else { return .none }
        if state.finishRestarts {
          // Done shows again after the relaunch, with fresh statuses; the onboarding isn't completed yet (S18, S68).
          state.progress.restarted = true
          return .concatenate(save(state), .run { _ in await system.relaunch() })
        }
        state.progress.completed = true
        state.progress.returnToDone = false
        return .concatenate(save(state), hide(&state, restoreFront: false))

      case let .turnOnTapped(permission):
        guard state.statuses[permission] == .notGranted, !state.turnOnIgnored.contains(permission) else { return .none }
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
          .run { send in
            try await clock.sleep(for: .seconds(10))
            await send(.guideExpired)
          }
          .cancellable(id: CancelID.guide, cancelInFlight: true),
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
        if permission == .pasteboard, !state.progress.pendingChecks.contains(.pasteboard) {
          state.progress.pendingChecks.insert(.pasteboard)
          effects.append(save(state))
        }
        return .merge(effects)

      case let .openPaneTapped(permission):
        state.guideArmed = permission
        return .merge(
          .run { _ in await permissions.openSettings(permission) },
          .run { send in
            try await clock.sleep(for: .seconds(10))
            await send(.guideExpired)
          }
          .cancellable(id: CancelID.guide, cancelInFlight: true)
        )

      case let .doneRowTapped(permission):
        guard state.page == .done, !state.isNavigationLocked, state.doneRows.contains(permission) else { return .none }
        state.progress.returnToDone = true
        return go(to: .holding(permission), &state)

      case .restartTapped:
        switch state.presentation {
        case let .single(single):
          // The page shows once more after the relaunch it starts (S50).
          state.progress.pendingSingle = single.permission
        case .flow:
          // The same page shows after the relaunch, with fresh statuses (S20); at most once (S68).
          guard !state.progress.restarted else { return .none }
          state.progress.restarted = true
        case .hidden:
          return .none
        }
        return .concatenate(save(state), .run { _ in await system.relaunch() })

      case .laterTapped:
        guard case .single = state.presentation else { return .none }
        return hide(&state, restoreFront: true)

      case .closeTapped:
        switch state.presentation {
        case .hidden: return .none
        case .flow: return hide(&state, restoreFront: false)
        case .single: return hide(&state, restoreFront: true)
        }

      case .escapePressed:
        guard case .single = state.presentation else { return .none }
        return hide(&state, restoreFront: true)

      case .backTapped:
        guard state.isPanel else { return .none }
        // Back cancels shrinking until the next request (S73).
        state.guideArmed = nil
        return leavePanel(&state)

      case .continueSetupTapped:
        // Always the onboarding at the saved page, replacing a single page (S80); the panel stays a panel (S69).
        guard !state.progress.completed else { return .none }
        if case .single = state.presentation {
          state.isPanel = false
          state.isPanelHidden = false
          state.guided = nil
        }
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

      case .openLoginItemsTapped:
        return .run { _ in await launchAtLogin.openSystemSettings() }

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
        guard case let .single(single) = state.presentation, single.isClosing else { return .none }
        // Blocked: the next missing required page, or close (S41).
        if single.kind == .blocked, let next = state.missingRequired.first {
          state.presentation = .single(SinglePage(permission: next, kind: .blocked))
          return .none
        }
        return hide(&state, restoreFront: true)

      case .loginItemTick:
        return .run { send in await send(.loginItemStatusLoaded(launchAtLogin.status())) }

      case .reset:
        state.progress = OnboardingProgress()
        state.settingsOpened = []
        state.turnOnIgnored = []
        state.openAtLoginChoice = true
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

  /// Shows `page`, saving it at once (S21) and holding the navigation buttons for 300 ms (S70).
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
    effects.append(page == .basics ? loginItemTicks() : .cancel(id: CancelID.loginItemTick))
    return .merge(effects)
  }

  /// Leaving Basics applies "Open at login" in release builds, once (S13, S74). A switch the user never touched turns
  /// it on only if Vortex never set it up before, so an earlier "off" stays off.
  private func applyLoginItemChoice(_ state: inout State) -> Effect<Action> {
    guard state.appliesLoginItem, !state.progress.loginItemApplied else { return .none }
    state.progress.loginItemApplied = true
    let choice = state.openAtLoginChoice
    return .run { send in
      if choice {
        await launchAtLogin.enableOnFirstLaunch()
        await send(.loginItemStatusLoaded(launchAtLogin.status()))
      } else {
        await send(.loginItemStatusLoaded(launchAtLogin.status()))
      }
    }
  }

  /// Basics re-reads the login item with the statuses, every second while it shows (S81).
  private func loginItemTicks() -> Effect<Action> {
    .run { send in
      await send(.loginItemTick)
      for await _ in clock.timer(interval: .seconds(1)) {
        await send(.loginItemTick)
      }
    }
    .cancellable(id: CancelID.loginItemTick, cancelInFlight: true)
  }

  private func save(_ state: State) -> Effect<Action> {
    // Synchronous: a forced quit right after a page change still resumes there (S71).
    progressClient.save(state.progress)
    return .none
  }

  // MARK: - Showing and hiding

  /// The onboarding at its page. A panel stays a panel and comes forward (S52, S69).
  private func showFlow(activate: Bool, _ state: inout State) -> Effect<Action> {
    let wasHidden = !state.isVisible
    if case .single = state.presentation { state.isPanel = false }
    state.presentation = .flow
    var effects: [Effect<Action>] = [present(state, activate: activate)]
    if wasHidden {
      effects.append(.run { _ in await permissions.setFrequentChecks(true) })
      if state.page == .basics { effects.append(loginItemTicks()) }
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
    // A request switches the page to the latest permission; a panel for the old one closes (S51).
    if state.isPanel, state.guided != permission {
      state.isPanel = false
      state.isPanelHidden = false
      state.guided = nil
    }
    state.guideArmed = nil
    var page = SinglePage(permission: permission, kind: kind)
    // Reopened after its relaunch and on already: ✓, then close (S50).
    if kind == .afterRelaunch, state.statuses[permission] == .granted { page.isClosing = true }
    state.presentation = .single(page)
    var effects: [Effect<Action>] = [present(state, activate: activate)]
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
      let target = OnboardingPage.holding(first)
      let firstBlockedPage = state.pages.first { page in state.rows(on: page).contains(where: state.isRequiredMissing) }
        ?? target
      if state.page != firstBlockedPage {
        state.progress.returnToDone = false
        effects.append(go(to: firstBlockedPage, &state))
      }
      effects.append(showFlow(activate: activate, &state))
      return .merge(effects)
    }
    if case let .single(single) = state.presentation, single.kind == .blocked, single.permission == first {
      return present(state, activate: activate)
    }
    return showSingle(first, .blocked, activate: activate, &state)
  }

  private func isShowingBlocking(_ state: State) -> Bool {
    switch state.presentation {
    case .hidden: false
    case .flow: !state.progress.completed
    case let .single(single): single.kind == .blocked
    }
  }

  private func present(_ state: State, activate: Bool) -> Effect<Action> {
    let mode: OnboardingWindowMode = state.isPanel ? (state.isPanelHidden ? .panelHidden : .panel) : .window
    return .run { _ in await window.present(mode, activate) }
  }

  private func hide(_ state: inout State, restoreFront: Bool) -> Effect<Action> {
    state.presentation = .hidden
    state.isPanel = false
    state.isPanelHidden = false
    state.guided = nil
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

  // MARK: - Requests, statuses and System Settings

  private func pageRequested(_ permission: Permission, _ kind: SinglePage.Kind, _ state: inout State) -> Effect<Action> {
    // While blocked every request shows the blocking page, whatever was asked for (S43).
    if !state.missingRequired.isEmpty { return showBlocking(activate: true, &state) }
    switch state.presentation {
    case .flow:
      // The onboarding comes to the front at its page; a panel stays a panel (S11, S52).
      return present(state, activate: true)
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
    if state.isPanel, let guided = state.guided, state.statuses[guided]?.isOn == true {
      effects.append(leavePanel(&state))
    }
    // A single page shows ✓ and closes after 1.5 s on a grant (S24, S41); not when the lock opened it (S55), and not
    // when the grant waits for a relaunch, which offers "Restart Vortex" and "Later".
    if case var .single(single) = state.presentation, !single.isClosing, single.kind != .lockRefused,
       state.statuses[single.permission] == .granted || (single.kind == .blocked && state.statuses[single.permission]?.isOn == true) {
      single.isClosing = true
      state.presentation = .single(single)
      effects.append(closeSingleLater())
    }
    if state.isVisible, state.page == .basics, case .flow = state.presentation {
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
        state.isPanel = true
        state.isPanelHidden = false
        state.guided = armed
        state.settingsOpened.insert(armed)
        state.isNotificationHintVisible = false
        return .merge(.cancel(id: CancelID.guide), present(state, activate: false))
      }
      if state.isPanel {
        // Placed again on each activation, and back if it stepped aside (S63, S73).
        state.isPanelHidden = false
        return present(state, activate: false)
      }
      return .none
    }
    guard state.isPanel else { return .none }
    let isVortex = bundleID == state.ownBundleID
    if isVortex == state.isPanelHidden {
      state.isPanelHidden = !isVortex
      return present(state, activate: false)
    }
    return .none
  }

  /// The panel turns back into the full window, in front (S15, S61).
  private func leavePanel(_ state: inout State) -> Effect<Action> {
    state.isPanel = false
    state.isPanelHidden = false
    state.guided = nil
    return present(state, activate: true)
  }
}
