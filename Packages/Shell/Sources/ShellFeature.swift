import ComposableArchitecture
import Foundation
import SwiftUI
import VortexCore
import VortexPlatform

extension Hotkey {
  static let openVortex = Hotkey("openVortex")

  /// Opens Vortex on a feature's tab. The shell owns these: features never open the window themselves.
  static func open(_ feature: FeatureID) -> Hotkey {
    Hotkey("open-\(feature)")
  }
}

/// The app shell: when the window opens and closes, which tab it shows, and the shell's settings.
@Reducer
struct ShellFeature {
  @ObservableState
  struct State: Equatable {
    var settings: ShellSettings
    /// Every registered feature, in registry order.
    var features: [FeatureDescriptor]
    var selectedTab: Tab = .settings
    var settingsSection: SettingsSection = .general
    /// The feature whose page Settings › Features shows; nil shows the list. Kept while the app runs, as the segment
    /// is, until that feature stops running.
    var settingsFeature: FeatureID?
    /// Why the window is open; nil while it is closed.
    var openReason: OpenReason?
    /// What feature tabs asked of the open window (`windowRequest`), until they ask again or it closes.
    var requests: [FeatureID: WindowRequest] = [:]
    /// The running features' widgets, as last told to Home (`@Shared(.runningHomeWidgets)`): at launch once every
    /// feature has started, then whenever the running features or their order change. Nil until the launch tells them.
    var homeWidgets: [HomeWidgetInfo]?
    /// "Add to Home" on features' pages, until Home takes each request.
    @Shared(.homeAddRequests) var homeAddRequests
    /// What Home tells back: the features with a widget on it.
    @SharedReader(.featuresOnHome) var featuresOnHome
    /// And the features whose "Add to Home" found no room; emptied whenever the tab changes.
    @Shared(.noRoomOnHome) var noRoomOnHome
    /// The feature whose ear the pointer is over in the closed notch; nil on the cutout and while the pointer is away.
    /// Hovering opens the window on that feature's tab.
    var hoveredEar: FeatureID?
    var isPointerInsideWindow = false
    /// Something of Vortex's is in use outside the window (a drag, Quick Look, the folder picker); it stays open meanwhile.
    var isHeldOpen = false
    /// Keyboard cleaning, which covers the window and keeps it open while the keys are locked.
    var keyboardCleaning = KeyboardCleaningFeature.State()
    /// False while a display without a notch is connected; the menu bar icon is the way in there.
    var everyScreenHasNotch = true
    /// Some connected display has a notch, so the notch is a way in.
    var hasNotchScreen = true
    var launchAtLogin: LaunchAtLoginStatus = .disabled
    /// The launch has switched every feature on or off; a QA run says it is ready only after this.
    var isStarted = false
    var language: AppLanguage
    /// Language the app was started with; another choice needs a relaunch.
    let launchLanguage: AppLanguage
    /// This build's version: Settings › General shows its short version, and the onboarding keeps it with what macOS
    /// granted.
    let appVersion: AppVersion
    /// What macOS says about each permission, as last read; empty until the first read. Only the shell writes it.
    @Shared(.permissionStatuses) var permissionStatuses
    /// A required permission that something enabled needs reads `notGranted`; follows `isBlocked`.
    @Shared(.appBlocked) var appBlocked
    /// The permissions Vortex can't be used without; QA mode may change them per run.
    var requiredPermissions = OnboardingConfig.requiredPermissions
    /// The first-run onboarding and the single permission page, in their own window.
    var onboarding: OnboardingFeature.State
    /// Features that bring their own onboarding step (`FeatureModule.hasOnboardingStep`), running or not.
    var stepFeatures: Set<FeatureID>
    /// An entry point used before the first status read; it is decided once the statuses are in.
    var pendingEntry: OpenReason?
    /// Vortex crashed early last launch and nobody can be blamed: only built-in features run, and those the user
    /// starts. Lasts this launch, or until "Start All".
    var isSafeMode: Bool
    /// Features the user started during safe mode.
    var safeModeStarted: Set<FeatureID> = []
    /// Features that were new when the user came into the catalog: they keep the badge until the user leaves it.
    var visitNew: Set<FeatureID> = []
    /// The feature just removed, while its Undo shows (5 s).
    var removedForUndo: FeatureID?
    /// Files given to Vortex while no running feature took them; the feature that takes files gets them once added.
    var pendingFiles: [URL] = []
    /// What a feature not added keeps on disk, in bytes, for its page; read as the page shows. Missing: nothing kept.
    var dataSizes: [FeatureID: Int64] = [:]
    /// The tab an entry point waiting for the first status read opens on; nil for the usual one.
    var pendingTab: Tab?
    /// The feature whose Erase Data asks for confirmation, in the window, which stays open meanwhile.
    var eraseConfirmation: FeatureID?

    /// `askedBefore`: what Vortex had asked macOS for, which a release that kept no grants yet counts as granted.
    init(
      settings: ShellSettings = ShellSettings(),
      features: [FeatureDescriptor] = [],
      language: AppLanguage = .system,
      onboarding: OnboardingProgress = OnboardingProgress(),
      stepFeatures: Set<FeatureID> = [],
      appVersion: AppVersion = .current,
      askedBefore: Set<Permission> = [],
      isSafeMode: Bool = false
    ) {
      // Settings written before the catalog, or by a test, count as an update: every feature that wasn't off is added.
      // A launch settles them first, telling a fresh install apart (ShellController).
      var settings = settings
      settings.settleAddedFeatures(all: features, isFreshInstall: false)
      self.settings = settings
      self.features = features
      self.language = language
      self.launchLanguage = language
      self.appVersion = appVersion
      self.onboarding = OnboardingFeature.State(progress: onboarding)
      self.stepFeatures = stepFeatures
      self.isSafeMode = isSafeMode
      self.selectedTab = restoredTab
      self.onboarding.appliesLoginItem = OnboardingConfig.appliesLoginItem
      self.onboarding.appVersion = appVersion.full
      self.onboarding.askedBefore = askedBefore
      onboardingContext.apply(to: &self.onboarding)
    }

    /// What Done's hint names, from the settings and screens: the notch only while a notch display is
    /// connected, by hover if that opens Vortex, else by click; the menu bar icon as it shows once the onboarding is
    /// done.
    var doneHint: OnboardingFeature.DoneHint {
      let notch: OnboardingFeature.DoneHint.Notch? = !hasNotchScreen
        ? nil : settings.openOnHover ? .hover : settings.openOnClick ? .click : nil
      return OnboardingFeature.DoneHint(notch: notch, menuBarIcon: settings.showMenuBarIcon || isMenuBarIconRequired)
    }

    var isOpen: Bool { openReason != nil }

    /// All features in the user's order, enabled or not.
    var orderedFeatures: [FeatureDescriptor] {
      let order = settings.featureOrder
      return features.enumerated()
        .sorted { lhs, rhs in
          (order.firstIndex(of: lhs.element.id) ?? order.count + lhs.offset)
            < (order.firstIndex(of: rhs.element.id) ?? order.count + rhs.offset)
        }
        .map(\.element)
    }

    /// The features the user added, in sidebar order; a built-in one always is. An added feature may still not run.
    var addedFeatures: [FeatureDescriptor] {
      orderedFeatures.filter(isAdded)
    }

    /// The added features whose code runs, in sidebar order: a built-in one always; any other once the user has chosen
    /// features, unless it is paused in this release or was stopped after a crash, and in safe mode only once the user
    /// starts it. Nothing of any other feature runs: no start, no views, no onboarding step, no notch indicator, no
    /// shortcut.
    var runningFeatures: [FeatureDescriptor] {
      addedFeatures.filter { feature in
        if feature.isBuiltIn { return true }
        guard settings.featuresChosen, feature.suspension == nil, !settings.stoppedFeatures.contains(feature.id) else {
          return false
        }
        return !isSafeMode || safeModeStarted.contains(feature.id)
      }
    }

    /// The sidebar shows the features that run.
    var sidebarFeatures: [FeatureDescriptor] {
      runningFeatures
    }

    /// Settings › Features: the running features with something to set, in sidebar order. That is every one: each has
    /// its tab, so its tab's shortcut, which its page shows before the feature's own settings (`makeSettings()`).
    var settingsFeatures: [FeatureDescriptor] {
      sidebarFeatures
    }

    /// Whether the feature has a page in Settings › Features; the Settings button on its catalog page shows only then.
    func hasSettingsPage(_ id: FeatureID) -> Bool {
      settingsFeatures.contains { $0.id == id }
    }

    /// The feature page Settings › Features shows, in that segment; nil for the list.
    var settingsPage: FeatureDescriptor? {
      settingsFeature.flatMap { id in settingsFeatures.first { $0.id == id } }
    }

    /// The permission a feature's yellow dot names: on its sidebar icon, its card in the catalog and its row in
    /// Settings › Features. The first it needs that reads `notGranted`; none before the first read.
    func permissionOff(for feature: FeatureDescriptor) -> Permission? {
      feature.permissionNeeds.firstOff(in: permissionStatuses)
    }

    /// Features whose notch indicators stay hidden: every feature that doesn't run, as one may leave its indicator
    /// behind when it stops. Keys that are no feature's id, such as `debug`, never hide.
    var hiddenIndicatorOwners: Set<FeatureID> {
      Set(features.map(\.id)).subtracting(runningFeatures.map(\.id))
    }

    /// Whether the user added the feature; a built-in one always is.
    func isAdded(_ feature: FeatureDescriptor) -> Bool {
      feature.isBuiltIn || (settings.addedFeatures ?? features.map(\.id)).contains(feature.id)
    }

    /// Adds or removes a feature, keeping `addedFeatures` in the registry's order; ids of features this build doesn't
    /// ship stay, so such a feature is still added if a later build brings it back.
    mutating func setAdded(_ id: FeatureID, _ isAdded: Bool) {
      var ids = settings.addedFeatures ?? features.map(\.id)
      if isAdded {
        if !ids.contains(id) { ids.append(id) }
      } else {
        ids.removeAll { $0 == id }
      }
      let order = features.map(\.id)
      settings.addedFeatures = order.filter(ids.contains) + ids.filter { !order.contains($0) }
    }

    /// The icon is the only way in while some display has no notch, or while the notch can't open Vortex.
    var isMenuBarIconRequired: Bool {
      !everyScreenHasNotch || !(settings.openOnHover || settings.openOnClick)
    }

    /// While blocked, or while the onboarding is unfinished, the icon shows even if the user hid it.
    var isMenuBarIconVisible: Bool {
      settings.showMenuBarIcon || isMenuBarIconRequired || isBlocked || !onboarding.progress.completed
    }

    /// The running feature that gets files given to Vortex, see `FeatureModule.acceptsFileDrops`.
    var fileFeature: FeatureDescriptor? {
      runningFeatures.first(where: \.acceptsFileDrops)
    }

    var needsRestartForLanguage: Bool {
      language != launchLanguage
    }

    /// The permissions the added features and the shell need, and why: a feature that waits for the user's choice or
    /// was stopped after a crash still needs its permissions; one paused in this release asks for none.
    var permissionCatalog: PermissionCatalog {
      PermissionCatalog(features: addedFeatures.filter { $0.suspension == nil }, required: requiredPermissions)
    }

    /// A required permission that something enabled needs reads `notGranted`; never before the first read.
    /// Checked after every action, so with nothing required it builds no catalog.
    var isBlocked: Bool {
      !requiredPermissions.isEmpty && !permissionCatalog.missingRequired(permissionStatuses).isEmpty
    }

    /// What the onboarding needs to know about the shell; kept current after every action.
    var onboardingContext: OnboardingContext {
      // Features with their own step, running or not, in sidebar order; only a running one shows its step.
      let stepOrder = orderedFeatures.map(\.id).filter(stepFeatures.contains)
      let running = Set(runningFeatures.map(\.id))
      // The Features page shows only in an onboarding not done yet; a finished one has nothing to choose there.
      let choosable = onboarding.progress.completed ? [] : catalogFeatures.filter { $0.suspension == nil }
      return OnboardingContext(
        catalog: permissionCatalog,
        steps: stepOrder.filter(running.contains),
        stepOrder: stepOrder,
        hint: doneHint,
        choosable: choosable,
        chosen: Set(choosable.filter(isAdded).map(\.id))
      )
    }

    /// Whether Vortex is blocked, and whether the statuses were read yet: the first read is the launch's, which the
    /// onboarding's `launched` decides; any later change to blocked is a revoke, a feature turned on or a new required
    /// set.
    var blockState: BlockState {
      BlockState(isRead: !permissionStatuses.isEmpty, isBlocked: isBlocked)
    }

    /// The last ordinary tab the user chose if it still exists; otherwise the first feature, then settings. The
    /// catalog is never restored: every open starts at the regular size.
    var restoredTab: Tab {
      if let last = settings.lastTab.map(Tab.init(storageValue:)), !last.isCatalog, isAvailable(last) {
        return last
      }
      return sidebarFeatures.first.map { .feature($0.id) } ?? .settings
    }

    func isAvailable(_ tab: Tab) -> Bool {
      switch tab {
      case .settings, .catalog: true
      case let .feature(id): sidebarFeatures.contains { $0.id == id }
      case let .catalogPage(id): features.contains { $0.id == id && !$0.isBuiltIn }
      }
    }

    /// The features the catalog shows: every feature but the built-in ones, in the user's order.
    var catalogFeatures: [FeatureDescriptor] {
      orderedFeatures.filter { !$0.isBuiltIn }
    }

    /// The catalog's "Added" section.
    var catalogAdded: [FeatureDescriptor] {
      catalogFeatures.filter(isAdded)
    }

    /// The catalog's "Can add" section: the recommended features first.
    var catalogAvailable: [FeatureDescriptor] {
      let available = features.filter { !$0.isBuiltIn && !isAdded($0) }
      return available.filter(\.isRecommended) + available.filter { !$0.isRecommended }
    }

    /// Features the catalog hasn't shown yet; one paused in this release is never new.
    var unseenFeatures: Set<FeatureID> {
      Set(catalogFeatures.filter { !settings.seenFeatures.contains($0.id) && $0.suspension == nil }.map(\.id))
    }

    /// Whether the catalog's sidebar icon has a dot: a feature is new, stopped after a crash, or waits in safe mode.
    var catalogDot: Bool {
      let running = Set(runningFeatures.map(\.id))
      return !unseenFeatures.isEmpty
        || catalogAdded.contains { feature in
          let isStopped = settings.stoppedFeatures.contains(feature.id)
          let waitsInSafeMode = isSafeMode && settings.featuresChosen && feature.suspension == nil && !isStopped
            && !running.contains(feature.id)
          return isStopped || waitsInSafeMode
        }
    }

    /// What a feature's page shows; nil for a built-in feature, which has none.
    func pageState(_ id: FeatureID) -> FeaturePageState? {
      guard let feature = features.first(where: { $0.id == id }), !feature.isBuiltIn else { return nil }
      if let reason = feature.suspension { return .paused(reason) }
      guard isAdded(feature) else {
        if let bytes = dataSizes[id] { return .removed(dataBytes: bytes) }
        return removedForUndo == id ? .removed(dataBytes: nil) : .available
      }
      if settings.stoppedFeatures.contains(id) { return .stopped }
      if isSafeMode, !runningFeatures.contains(where: { $0.id == id }) { return .waitingInSafeMode }
      return .added(needsSetup: feature.hasOnboardingStep && !onboarding.stepsDone.contains(id))
    }

    /// The catalog needs the large window; a feature's tab has the window it asked for, and every other tab the
    /// regular one.
    var windowSize: WindowSize {
      if selectedTab.isCatalog { return .large }
      guard case let .feature(id) = selectedTab else { return .regular }
      return requests[id]?.size ?? .regular
    }

    /// What a feature's page says about Home: nothing unless the feature runs with widgets; "On Home" while one of them
    /// is on it; "Add to Home" otherwise, with "No room on Home" under the buttons once Home found no room for it.
    func homeOnPage(_ id: FeatureID) -> HomeOnPage? {
      guard case .added = pageState(id), (homeWidgets ?? []).contains(where: { $0.feature == id }) else { return nil }
      if featuresOnHome.contains(id) { return .onHome }
      return noRoomOnHome.contains(id) ? .noRoom : .canAdd
    }

    /// The feature whose tab has the focus: the sidebar dims, and the other tabs and their shortcuts wait.
    var focusedFeature: FeatureID? {
      guard case let .feature(id) = selectedTab, requests[id]?.isFocused == true else { return nil }
      return id
    }

    /// The size of the open window; nil while it is closed. An open sets the size itself, as it shows the window.
    var openWindowSize: WindowSize? {
      isOpen ? windowSize : nil
    }
  }

  /// A feature's page and Home: whether "Add to Home" shows, or "On Home".
  enum HomeOnPage: Equatable, Sendable {
    case canAdd
    /// "Add to Home" found no room: the button stays, and a line under the buttons says why nothing happened.
    case noRoom
    case onHome
  }

  /// What a feature's page in the catalog shows, and which buttons.
  enum FeaturePageState: Equatable, Sendable {
    case available
    /// `needsSetup`: the feature's own onboarding step isn't done; the page shows it.
    case added(needsSetup: Bool)
    /// Not added, with what it still keeps on disk, if known.
    case removed(dataBytes: Int64?)
    /// Paused by the maintainer in this release, with the reason.
    case paused(LocalizedStringResource)
    /// Stopped after Vortex crashed in it.
    case stopped
    /// Added, waiting in safe mode for the user to start it.
    case waitingInSafeMode
  }

  struct OnboardingContext: Equatable, Sendable {
    var catalog: PermissionCatalog
    var steps: [FeatureID]
    var stepOrder: [FeatureID]
    var hint: OnboardingFeature.DoneHint
    var choosable: [FeatureDescriptor]
    var chosen: Set<FeatureID>

    func apply(to onboarding: inout OnboardingFeature.State) {
      onboarding.catalog = catalog
      onboarding.steps = steps
      onboarding.stepOrder = stepOrder
      onboarding.doneHint = hint
      onboarding.choosable = choosable
      onboarding.chosen = chosen
    }
  }

  struct BlockState: Equatable, Sendable {
    var isRead: Bool
    var isBlocked: Bool
  }

  enum Tab: Hashable, Sendable {
    case feature(FeatureID)
    case settings
    /// The catalog's list of features.
    case catalog
    /// A feature's page in the catalog.
    case catalogPage(FeatureID)

    /// The catalog and its pages, which the large window shows and `lastTab` never keeps.
    var isCatalog: Bool {
      switch self {
      case .catalog, .catalogPage: true
      case .feature, .settings: false
      }
    }

    var storageValue: String {
      switch self {
      case let .feature(id): "feature:\(id)"
      case .settings: "settings"
      case .catalog: "catalog"
      case let .catalogPage(id): "catalog:\(id)"
      }
    }

    init(storageValue: String) {
      if storageValue.hasPrefix("feature:") {
        self = .feature(String(storageValue.dropFirst("feature:".count)))
      } else if storageValue == "catalog" {
        self = .catalog
      } else if storageValue.hasPrefix("catalog:") {
        self = .catalogPage(String(storageValue.dropFirst("catalog:".count)))
      } else {
        self = .settings
      }
    }
  }

  enum SettingsSection: CaseIterable, Sendable {
    case general
    case activation
    case features
  }

  enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case task
    case window(WindowEvent)
    case openHotkeyPressed
    case featureHotkeyPressed(FeatureID)
    /// Files opened with Vortex, e.g. by `vortex shelf add`.
    case filesReceived([URL])
    case hoverDelayElapsed
    case pointerLeaveDelayElapsed
    case tabSelected(Tab)
    /// A feature's tab asks for a window size and the focus (`windowRequest` in its environment).
    case windowRequested(FeatureID, WindowRequest)
    /// "Add to Home" on a feature's page.
    case addToHomeTapped(FeatureID)
    /// The running features' widgets, read anew for Home.
    case homeWidgetsLoaded([HomeWidgetInfo])
    case featureDropped(FeatureID, onto: FeatureID)
    case settingsShown
    case launchAtLoginChanged(Bool)
    case launchAtLoginStatusLoaded(LaunchAtLoginStatus)
    /// Every feature has been started or stopped at launch.
    case started
    case openLoginItemsTapped
    case menuOpenTapped
    case menuSettingsTapped
    case restartButtonTapped
    case quitButtonTapped
    /// Settings › General's "Check for Updates".
    case checkForUpdatesTapped
    case keyboardCleaning(KeyboardCleaningFeature.Action)
    /// Safe mode's "Start All": every added feature that waits starts, each on a trial, and safe mode ends.
    case startAllTapped
    /// Starts one feature in safe mode, on a trial.
    case startFeatureTapped(FeatureID)
    /// Starts a feature stopped after a crash again, on a trial.
    case tryAgainTapped(FeatureID)
    /// A feature's page: Add. The feature starts on a trial, and its tab is the one the window opens on next.
    case featureAdded(FeatureID)
    /// A feature's page: Remove. The feature stops, and Undo shows for 5 s.
    case featureRemoved(FeatureID)
    case undoRemoveTapped
    case undoExpired
    /// A feature's page: Open, which goes to its tab.
    case openFeatureTapped(FeatureID)
    /// A feature's page: Settings, which goes to the feature's own page in Settings › Features.
    case featureSettingsTapped(FeatureID)
    /// Settings › Features: a feature's row, which opens its page.
    case settingsRowTapped(FeatureID)
    /// A feature's page in Settings › Features: "‹ Features", back to the list.
    case settingsBackTapped
    /// A removed feature's page: Erase Data, which asks first.
    case eraseTapped(FeatureID)
    case eraseCancelled
    /// The feature is left to erase at the next launch, before anything starts, and Vortex restarts.
    case eraseConfirmed
    /// A feature's page showed: it reads what the feature keeps on disk.
    case featurePageShown(FeatureID)
    case dataSizeLoaded(FeatureID, Int64?)
    /// macOS's statuses, at the first read and on every change.
    case permissionStatusesChanged([Permission: PermissionStatus])
    /// A feature asked for the page of one permission.
    case permissionPageRequested(Permission)
    /// «Continue setup» in the menu bar menu, and QA's `onboarding open`.
    case continueSetupTapped
    case onboarding(OnboardingFeature.Action)
    /// An app came to the front, or quit: the guide panel follows System Settings.
    case appActivated(String)
    case appTerminated(String)
  }

  @Dependency(\.activeAppClient) var activeApp
  @Dependency(\.continuousClock) var clock
  @Dependency(\.featuresClient) var features
  @Dependency(\.fileClient) var files
  @Dependency(\.hotkeyClient) var hotkeys
  @Dependency(\.launchGuard) var launchGuard
  @Dependency(\.launchAtLoginClient) var launchAtLogin
  @Dependency(\.permissionPage) var permissionPage
  @Dependency(\.permissionsClient) var permissions
  @Dependency(\.settingsClient) var settingsClient
  @Dependency(\.systemClient) var system
  @Dependency(\.systemSettingsNamesClient) var systemSettingsNames
  @Dependency(\.windowClient) var window

  private enum CancelID: Hashable {
    case hoverOpen
    case pointerLeaveClose
    case saveSettings
    /// The listener for the shortcut that opens a feature's tab.
    case tabHotkey(FeatureID)
    case undoRemove
    /// Reading the running features' widgets for Home.
    case homeWidgets
  }

  /// The newest release on GitHub. "Check for Updates" opens it in the browser: Vortex itself never goes online.
  static let latestReleaseURL = URL(string: "https://github.com/OrtexIsArtem/vortex/releases/latest")!

  var body: some ReducerOf<Self> {
    CombineReducers {
      BindingReducer()
      Scope(state: \.keyboardCleaning, action: \.keyboardCleaning) {
        KeyboardCleaningFeature()
      }
      Scope(state: \.onboarding, action: \.onboarding) {
        OnboardingFeature()
      }
      Reduce { state, action in
        switch action {
        case .binding:
          return .none

        case .keyboardCleaning(.stopTapped):
          // The keyboard is back on: the window closes, and the keys go back to the app the user was in. A required
          // permission that went during the lock blocks only now.
          let effect = close(&state)
          return state.isBlocked ? .merge(effect, .send(.onboarding(.blocked))) : effect

        case .keyboardCleaning(.accessLost), .keyboardCleaning(.lockFailed):
          // The lock ended by itself, and Home with its warning shows; blocked meanwhile, the blocking page takes over
          // now, as after «Turn the keyboard back on».
          guard state.isBlocked else { return .none }
          return .merge(close(&state), .send(.onboarding(.blocked)))

        case let .keyboardCleaning(.delegate(.openPage(lockRefused))):
          // Opening a page closes the notch window first.
          return .merge(
            close(&state),
            .send(.onboarding(.pageRequested(.accessibility, lockRefused ? .lockRefused : .request)))
          )

        case .keyboardCleaning:
          return .none

        case let .onboarding(.featureToggled(id)):
          // Added or removed at once, without a trial or a page: before the user's choice nothing runs anyway, and the
          // onboarding then asks only for the chosen features' permissions.
          guard let feature = state.features.first(where: { $0.id == id }), !feature.isBuiltIn, feature.suspension == nil
          else { return .none }
          state.setAdded(id, !state.isAdded(feature))
          return .none

        case .onboarding:
          return .none

        case let .appActivated(bundleID):
          return .send(.onboarding(.appActivated(bundleID)))

        case let .appTerminated(bundleID):
          return .send(.onboarding(.appTerminated(bundleID)))

        case .task:
          // Erases left for this launch run first, before any feature does. They leave the list, saved at once, before
          // they run, so a crash inside one can't repeat at every launch. A feature added again meanwhile keeps its data.
          let erasing = state.settings.pendingErase.filter { id in
            !state.features.contains { $0.id == id && state.isAdded($0) }
          }
          if !state.settings.pendingErase.isEmpty {
            state.settings.pendingErase = []
            _ = saveSettingsNow(state)
          }
          // Only the running features start; nothing of the others runs, not even a stop.
          let running = state.runningFeatures.map(\.id)
          return .merge(
            .run { [
              isVisible = state.isMenuBarIconVisible,
              acceptsFiles = state.fileFeature != nil,
              hidden = state.hiddenIndicatorOwners
            ] send in
              await window.setMenuBarIconVisible(isVisible)
              await window.setAcceptsFiles(acceptsFiles)
              await window.setHiddenIndicatorOwners(hidden)
              for await event in await window.events() {
                await send(.window(event))
              }
            },
            .run { send in
              for await _ in hotkeys.presses(.openVortex) {
                await send(.openHotkeyPressed)
              }
            },
            .merge(running.map(listenForTabHotkey)),
            .concatenate(
              .run { [theme = state.settings.theme] send in
                await system.applyTheme(theme)
                for id in erasing {
                  await features.eraseData(id)
                }
                for id in running {
                  await features.setEnabled(id, true)
                }
                // No silent registration at launch: the onboarding's Basics applies "Open at login".
                await send(.launchAtLoginStatusLoaded(launchAtLogin.status()))
                // Before any onboarding page shows its drawing of System Settings.
                await send(.onboarding(.systemSettingsNamesLoaded(systemSettingsNames.names())))
                await send(.started)
              },
              // Once every feature has started, Home hears of the widgets that run, even of none, as in safe mode.
              tellHome(running, current: nil)
            ),
            .run { send in
              for await statuses in permissions.updates() {
                await send(.permissionStatusesChanged(statuses))
              }
            },
            .run { send in
              for await permission in permissionPage.requests() {
                await send(.permissionPageRequested(permission))
              }
            },
            .run { send in
              for await bundleID in activeApp.activations() {
                await send(.appActivated(bundleID))
              }
            },
            .run { send in
              for await bundleID in activeApp.terminations() {
                await send(.appTerminated(bundleID))
              }
            }
          )

        case let .window(event):
          return handle(event, state: &state)

        case .openHotkeyPressed:
          return state.isOpen ? close(&state) : open(.hotkey, &state)

        case let .featureHotkeyPressed(id):
          let tab = Tab.feature(id)
          guard state.isAvailable(tab), state.focusedFeature ?? id == id else { return .none }
          if state.isOpen, state.selectedTab == tab { return close(&state) }
          let effect = state.isOpen ? .none : open(.hotkey, &state)
          state.selectedTab = tab
          state.settings.lastTab = tab.storageValue
          return effect

        case let .filesReceived(urls):
          return deliver(urls, &state)

        case .hoverDelayElapsed:
          guard !state.isOpen else { return .none }
          // What counts is where the pointer is now, when the delay ends.
          return open(.hover, onEarOf: state.hoveredEar, &state)

        case .pointerLeaveDelayElapsed:
          guard state.isOpen, !state.isPointerInsideWindow, !state.isHeldOpen else { return .none }
          return close(&state)

        case let .tabSelected(tab):
          guard state.isAvailable(tab), state.focusedFeature.map({ tab == .feature($0) }) ?? true else { return .none }
          state.selectedTab = tab
          guard tab.isCatalog else {
            state.settings.lastTab = tab.storageValue
            return .none
          }
          // Going to the catalog is a deliberate open, as a click on the notch is: the window no longer closes when the
          // pointer leaves it, and certainly not as it grows away from a still pointer.
          guard state.isOpen else { return .none }
          state.openReason = .click
          return .cancel(id: CancelID.pointerLeaveClose)

        case let .addToHomeTapped(id):
          // Once: Home takes the request away when it has placed the widget or found no room.
          guard !state.homeAddRequests.contains(id) else { return .none }
          state.$homeAddRequests.withLock { $0.append(id) }
          return .none

        case let .homeWidgetsLoaded(widgets):
          state.homeWidgets = widgets
          // Written here, in the order the reads arrive, not by an effect of its own that could land after a newer one.
          @Shared(.runningHomeWidgets) var running
          $running.withLock { $0 = widgets }
          return .none

        case let .windowRequested(id, request):
          // Only while the window is open: a tab left mounted behind the closed window can't make the next open large.
          guard state.isOpen else { return .none }
          state.requests[id] = request == .regular ? nil : request
          // Growing or taking the focus is deliberate, as going to the catalog is: the window no longer closes when the
          // pointer leaves it.
          guard request != .regular else { return .none }
          state.openReason = .click
          return .cancel(id: CancelID.pointerLeaveClose)

        case let .featureDropped(dragged, onto: target):
          var ids = state.orderedFeatures.map(\.id)
          guard let from = ids.firstIndex(of: dragged), let to = ids.firstIndex(of: target), from != to else { return .none }
          ids.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
          state.settings.featureOrder = ids
          return .none


        case .settingsShown:
          // The user may have changed the login item in System Settings meanwhile.
          return .run { send in await send(.launchAtLoginStatusLoaded(launchAtLogin.status())) }

        case let .launchAtLoginChanged(isEnabled):
          return .run { send in await send(.launchAtLoginStatusLoaded(launchAtLogin.setEnabled(isEnabled))) }

        case let .launchAtLoginStatusLoaded(status):
          state.launchAtLogin = status
          return .none

        case .started:
          state.isStarted = true
          return .none

        case .startAllTapped:
          guard state.isSafeMode else { return .none }
          let before = state.runningFeatures.map(\.id)
          state.isSafeMode = false
          state.safeModeStarted = []
          beginTrials(of: state.runningFeatures.map(\.id).filter { !before.contains($0) })
          return .none

        case let .startFeatureTapped(id):
          guard state.isSafeMode, !state.safeModeStarted.contains(id) else { return .none }
          let before = state.runningFeatures.map(\.id)
          state.safeModeStarted.insert(id)
          beginTrials(of: state.runningFeatures.map(\.id).filter { !before.contains($0) })
          return .none

        case let .featureAdded(id):
          return add(id, &state)

        case let .featureRemoved(id):
          guard let feature = state.features.first(where: { $0.id == id }), !feature.isBuiltIn, state.isAdded(feature)
          else { return .none }
          state.setAdded(id, false)
          state.safeModeStarted.remove(id)
          state.removedForUndo = id
          var effects: [Effect<Action>] = [
            saveSettingsNow(state),
            .run { send in
              try await clock.sleep(for: .seconds(5))
              await send(.undoExpired)
            }
            .cancellable(id: CancelID.undoRemove, cancelInFlight: true),
          ]
          // A permission page only this feature asked for goes with it; the blocking page stays until the user closes it.
          if let single = state.onboarding.single, single.kind == .request,
             state.permissionCatalog.entry(for: single.permission) == nil {
            effects.append(.send(.onboarding(.closeTapped)))
          }
          return .merge(effects)

        case .undoRemoveTapped:
          guard let id = state.removedForUndo else { return .none }
          state.removedForUndo = nil
          return .merge(.cancel(id: CancelID.undoRemove), add(id, &state))

        case .undoExpired:
          state.removedForUndo = nil
          return .none

        case let .openFeatureTapped(id):
          let tab = Tab.feature(id)
          guard state.isAvailable(tab) else { return .none }
          state.selectedTab = tab
          state.settings.lastTab = tab.storageValue
          return .none

        case let .featureSettingsTapped(id):
          // Straight to the feature's own page, in the regular window; Settings is the tab the window opens on next.
          guard state.hasSettingsPage(id), state.focusedFeature == nil else { return .none }
          state.selectedTab = .settings
          state.settings.lastTab = Tab.settings.storageValue
          state.settingsSection = .features
          state.settingsFeature = id
          return .none

        case let .settingsRowTapped(id):
          guard state.hasSettingsPage(id) else { return .none }
          state.settingsFeature = id
          return .none

        case .settingsBackTapped:
          state.settingsFeature = nil
          return .none

        case let .eraseTapped(id):
          // Only a feature that isn't added has data to erase from its page.
          guard let feature = state.features.first(where: { $0.id == id }), !feature.isBuiltIn, !state.isAdded(feature)
          else { return .none }
          state.eraseConfirmation = id
          return .none

        case .eraseCancelled:
          state.eraseConfirmation = nil
          return .none

        case .eraseConfirmed:
          guard let id = state.eraseConfirmation else { return .none }
          state.eraseConfirmation = nil
          if !state.settings.pendingErase.contains(id) { state.settings.pendingErase.append(id) }
          // On disk before the restart, which erases it before anything starts (`.task`).
          _ = saveSettingsNow(state)
          return .run { _ in await system.relaunch() }

        case let .featurePageShown(id):
          return .run { send in await send(.dataSizeLoaded(id, features.dataSize(id))) }

        case let .dataSizeLoaded(id, bytes):
          state.dataSizes[id] = bytes
          return .none

        case let .tryAgainTapped(id):
          guard state.settings.stoppedFeatures.contains(id) else { return .none }
          let before = state.runningFeatures.map(\.id)
          state.settings.stoppedFeatures.removeAll { $0 == id }
          if state.isSafeMode { state.safeModeStarted.insert(id) }
          beginTrials(of: state.runningFeatures.map(\.id).filter { !before.contains($0) })
          return saveSettingsNow(state)

        case .openLoginItemsTapped:
          return .run { _ in await launchAtLogin.openSystemSettings() }

        case .menuOpenTapped:
          return state.isOpen ? .none : open(.menuBarIcon, &state)

        case .menuSettingsTapped:
          let effect = state.isOpen ? .none : open(.menuBarIcon, &state)
          state.selectedTab = .settings
          return effect

        case .restartButtonTapped:
          // Settings are written when the app terminates (ShellController.saveSettings).
          return .run { _ in await system.relaunch() }

        case .quitButtonTapped:
          return .run { _ in await system.quit() }

        case .checkForUpdatesTapped:
          return .run { _ in await files.open(Self.latestReleaseURL) }

        case let .permissionStatusesChanged(statuses):
          let old = state.permissionStatuses
          state.$permissionStatuses.withLock { $0 = statuses }
          var effects: [Effect<Action>] = [.send(.onboarding(.statusesChanged(old: old)))]
          // While the keyboard is locked, losing Accessibility ends the lock at once; no page opens by itself.
          if state.keyboardCleaning.isLocked, statuses[.accessibility] == .notGranted {
            effects.append(.send(.keyboardCleaning(.accessLost)))
          }
          if old.isEmpty {
            // The first read: the onboarding shows if it isn't done, and an entry point waiting for it goes on.
            // A notch window opened before it closes first when the onboarding window shows.
            if state.onboarding.showsAtLaunch { effects.append(close(&state)) }
            effects.append(.send(.onboarding(.launched)))
            if let reason = state.pendingEntry {
              let tab = state.pendingTab
              state.pendingEntry = nil
              state.pendingTab = nil
              effects.append(open(reason, &state, tab: tab))
            }
          }
          return .merge(effects)

        case .continueSetupTapped:
          // Bringing the onboarding forward closes the notch window first, as every other way does.
          guard !state.onboarding.progress.completed else { return .none }
          return .merge(close(&state), .send(.onboarding(.continueSetupTapped)))

        case let .permissionPageRequested(permission):
          // The page opens in the onboarding's window; the notch window closes first, except over the lock.
          return .merge(close(&state), .send(.onboarding(.pageRequested(permission, .request))))
        }
      }
    }
    .onChange(of: \.blockState) { old, new in
      Reduce { state, _ in
        state.$appBlocked.withLock { $0 = new.isBlocked }
        // Becoming blocked after the launch's read, however it happened: the notch window closes and the blocking page
        // opens. During a lock this waits for the lock to end.
        guard new.isBlocked, !old.isBlocked, old.isRead, !state.keyboardCleaning.isLocked else { return .none }
        return .merge(close(&state), .send(.onboarding(.blocked)))
      }
    }
    .onChange(of: \.onboarding.progress.page) { old, _ in
      Reduce { state, _ in
        // Leaving the Features page is the user's choice: from now on the chosen features run. Before the observer of
        // `runningFeatures` below, so it starts them in this same action.
        if old == OnboardingPage.features.id { state.settings.featuresChosen = true }
        return .none
      }
    }
    .onChange(of: \.onboarding.isVisible) { _, isVisible in
      Reduce { state, _ in
        // So is closing the onboarding, wherever it was.
        if !isVisible { state.settings.featuresChosen = true }
        return .none
      }
    }
    .onChange(of: \.runningFeatures) { old, new in
      Reduce { state, _ in
        // Home hears of the widgets even when only the order changed: its panel lists them in sidebar order.
        .merge(syncRunning(from: old, to: new, &state), tellHome(new.map(\.id), current: state.homeWidgets ?? []))
      }
    }
    .onChange(of: \.onboardingContext) { _, context in
      Reduce { state, _ in
        context.apply(to: &state.onboarding)
        return .none
      }
    }
    .onChange(of: \.settings) { _, settings in
      Reduce { _, _ in
        .run { _ in
          try await clock.sleep(for: .milliseconds(400))
          try settingsClient.save(settings)
        }
        .cancellable(id: CancelID.saveSettings, cancelInFlight: true)
      }
    }
    .onChange(of: \.settings.theme) { _, theme in
      Reduce { _, _ in
        .run { _ in await system.applyTheme(theme) }
      }
    }
    .onChange(of: \.language) { _, language in
      Reduce { _, _ in
        .run { _ in system.setLanguage(language) }
      }
    }
    .onChange(of: \.selectedTab) { _, _ in
      Reduce { state, _ in
        // "No room on Home" speaks only for the page in view: it goes as the page is left, and a page coming into view
        // never shows an answer to a request made on an earlier visit.
        if !state.noRoomOnHome.isEmpty { state.$noRoomOnHome.withLock { $0 = [] } }
        return .none
      }
    }
    .onChange(of: \.selectedTab.isCatalog) { _, isInCatalog in
      Reduce { state, _ in
        if isInCatalog {
          // The features that are new keep their badge for this visit; from now on every feature counts as seen.
          state.visitNew = state.unseenFeatures
          state.settings.seenFeatures = state.features.map(\.id)
        } else {
          state.visitNew = []
        }
        return .none
      }
    }
    .onChange(of: \.openWindowSize) { old, new in
      Reduce { _, _ in
        // Only while it stays open: a window that opens takes the size of its tab as it shows.
        guard old != nil, let new else { return .none }
        return .run { _ in await window.setSize(new) }
      }
    }
    .onChange(of: \.isMenuBarIconVisible) { _, isVisible in
      Reduce { _, _ in
        .run { _ in await window.setMenuBarIconVisible(isVisible) }
      }
    }
    .onChange(of: \.fileFeature) { _, feature in
      Reduce { _, _ in
        .run { _ in await window.setAcceptsFiles(feature != nil) }
      }
    }
  }

  /// Marks the features about to start as on trial, before they start: done here, not in an effect, so the mark is on
  /// disk before any of their code runs (`.onChange(of: \.runningFeatures)` starts them after this action).
  private func beginTrials(of ids: [FeatureID]) {
    for id in ids {
      launchGuard.beginTrial(id)
    }
  }

  /// Writes the settings now rather than after the usual 400 ms: a change that starts a feature must be on disk before
  /// the feature's code runs, in case it brings Vortex down. Done here, not in an effect, for that order.
  private func saveSettingsNow(_ state: State) -> Effect<Action> {
    try? settingsClient.save(state.settings)
    return .none
  }

  /// However the features that run changed (added, removed, chosen, stopped after a crash): each one that stopped runs
  /// nothing anymore, each new one starts, and the sidebar leaves a tab that went, as Settings › Features leaves its
  /// page.
  private func syncRunning(
    from old: [FeatureDescriptor],
    to new: [FeatureDescriptor],
    _ state: inout State
  ) -> Effect<Action> {
    let oldIDs = old.map(\.id)
    let newIDs = new.map(\.id)
    let stopped = oldIDs.filter { !newIDs.contains($0) }
    let started = newIDs.filter { !oldIDs.contains($0) }
    guard !stopped.isEmpty || !started.isEmpty else { return .none }
    if !state.isAvailable(state.selectedTab) {
      state.selectedTab = state.restoredTab
    }
    if let id = state.settingsFeature, !state.hasSettingsPage(id) {
      state.settingsFeature = nil
    }
    let hidden = state.hiddenIndicatorOwners
    // Files that waited for a feature that takes them go to it once it runs.
    var waitingFiles: (id: FeatureID, urls: [URL])?
    if let taker = state.fileFeature, started.contains(taker.id), !state.pendingFiles.isEmpty {
      waitingFiles = (taker.id, state.pendingFiles)
      state.pendingFiles = []
    }
    let cancellations: [Effect<Action>] = stopped.map { .cancel(id: CancelID.tabHotkey($0)) }
    return .merge(
      .merge(cancellations),
      .merge(started.map(listenForTabHotkey)),
      .run { [waitingFiles] _ in
        for id in stopped {
          await features.setEnabled(id, false)
        }
        for id in started {
          await features.setEnabled(id, true)
        }
        await window.setHiddenIndicatorOwners(hidden)
        if let waitingFiles {
          await features.receiveFiles(waitingFiles.id, waitingFiles.urls)
        }
      }
    )
  }

  /// Reads the running features' widgets for Home, which follows them whether its tab shows or not, and tells them unless
  /// they are `current`; nil tells them in any case. The newest read wins.
  private func tellHome(_ running: [FeatureID], current: [HomeWidgetInfo]?) -> Effect<Action> {
    .run { send in
      let widgets = await features.homeWidgets(running)
      if widgets != current { await send(.homeWidgetsLoaded(widgets)) }
    }
    .cancellable(id: CancelID.homeWidgets, cancelInFlight: true)
  }

  /// Listens for the shortcut that opens the feature's tab while the feature runs; cancelling it frees the keys.
  private func listenForTabHotkey(_ id: FeatureID) -> Effect<Action> {
    .run { send in
      for await _ in hotkeys.presses(.open(id)) {
        await send(.featureHotkeyPressed(id))
      }
    }
    .cancellable(id: CancelID.tabHotkey(id), cancelInFlight: true)
  }

  private func handle(_ event: WindowEvent, state: inout State) -> Effect<Action> {
    switch event {
    case let .notchHoverChanged(isInside):
      guard isInside else {
        state.hoveredEar = nil
        return .cancel(id: CancelID.hoverOpen)
      }
      guard !state.isOpen, state.settings.openOnHover else { return .none }
      return .run { [delay = state.settings.hoverDelay] send in
        try await clock.sleep(for: .seconds(delay))
        await send(.hoverDelayElapsed)
      }
      .cancellable(id: CancelID.hoverOpen, cancelInFlight: true)

    case let .notchPointerOver(feature):
      state.hoveredEar = feature
      return .none

    case let .notchClicked(feature):
      switch state.openReason {
      case nil:
        guard state.settings.openOnClick else { return .none }
        return open(.click, onEarOf: feature, &state)
      case let reason? where reason.isPassing:
        // Clicking a window that opened on the way past keeps it open, as if the click had opened it.
        state.openReason = .click
        return .cancel(id: CancelID.pointerLeaveClose)
      case .some:
        return close(&state)
      }

    case .fileDragEnteredNotch:
      // Dragging past the notch does nothing while no feature takes files (CLAUDE.md, architecture rule 4).
      guard state.fileFeature != nil else { return .none }
      if state.isOpen {
        selectDropTab(&state)
        return .none
      }
      return open(.fileDrag, &state)

    case .menuBarIconClicked:
      return state.isOpen ? close(&state) : open(.menuBarIcon, &state)

    case let .filesDroppedOnMenuBarIcon(urls):
      return deliver(urls, &state)

    case let .pointerInsideWindowChanged(isInside):
      state.isPointerInsideWindow = isInside
      return isInside ? .cancel(id: CancelID.pointerLeaveClose) : schedulePointerLeaveClose(state)

    case let .outsideActivityChanged(isActive):
      state.isHeldOpen = isActive
      return isActive ? .cancel(id: CancelID.pointerLeaveClose) : .none

    case .clickedOutside:
      guard state.isOpen, state.settings.closeOnClickOutside, !state.isHeldOpen else { return .none }
      return close(&state)

    case .escapePressed:
      guard state.isOpen else { return .none }
      // Esc answers the erase question with Cancel.
      if state.eraseConfirmation != nil {
        state.eraseConfirmation = nil
        return .none
      }
      // From a feature's page Esc goes back to the catalog's list.
      if case .catalogPage = state.selectedTab {
        state.selectedTab = .catalog
        return .none
      }
      // So does it from a feature's page in Settings › Features, to the list there.
      if state.selectedTab == .settings, state.settingsSection == .features, state.settingsPage != nil {
        state.settingsFeature = nil
        return .none
      }
      return close(&state)

    case let .screensChanged(everyScreenHasNotch, anyScreenHasNotch):
      state.everyScreenHasNotch = everyScreenHasNotch
      state.hasNotchScreen = anyScreenHasNotch
      guard let reason = state.openReason else { return .none }
      // A window kept open for keyboard cleaning moves to the new screens; any other was placed for the old ones.
      return state.keyboardCleaning.isLocked ? .run { _ in await window.present(reason) } : close(&state)

    case let .keyPressedWhileHeld(key):
      // The key went nowhere, but the lock screen washes it as if the lock had held it back.
      return .send(.keyboardCleaning(.keyPressed(key)))
    }
  }

  /// Opens the window on `tab`, or on the tab to restore.
  private func open(_ reason: OpenReason, _ state: inout State, tab: Tab? = nil) -> Effect<Action> {
    // Entry points wait for the first status read before deciding.
    if !state.requiredPermissions.isEmpty, state.permissionStatuses.isEmpty {
      state.pendingEntry = reason
      state.pendingTab = tab
      return .cancel(id: CancelID.hoverOpen)
    }
    // Blocked: every entry point opens the blocking page instead; a hover shows it without activating.
    if state.isBlocked {
      return .merge(
        .cancel(id: CancelID.hoverOpen),
        close(&state),
        .send(.onboarding(.blockedEntry(activate: reason != .hover)))
      )
    }
    state.openReason = reason
    state.selectedTab = tab ?? state.restoredTab
    if reason == .fileDrag { selectDropTab(&state) }
    return .merge(
      .cancel(id: CancelID.hoverOpen),
      // The window opens at the size of its tab, set before it shows: the regular one, unless it opens in the catalog.
      .run { [size = state.windowSize] _ in
        await window.setSize(size)
        await window.present(reason)
      },
      // Notifications send no signal when they change, and the window opening activates no app: read again.
      .run { _ in await permissions.refresh() }
    )
  }

  /// Opens on the tab of the feature whose ear the pointer is on, without changing the remembered tab. Over the cutout,
  /// or when the feature is off or has no tab, it opens the last tab.
  private func open(_ reason: OpenReason, onEarOf feature: FeatureID?, _ state: inout State) -> Effect<Action> {
    let effect = open(reason, &state)
    if let feature, state.isAvailable(.feature(feature)) {
      state.selectedTab = .feature(feature)
    }
    return effect
  }

  private func close(_ state: inout State) -> Effect<Action> {
    // Keyboard cleaning keeps the window open until the user turns the keyboard back on, and the erase question until
    // the user answers it.
    guard !state.keyboardCleaning.isLocked, state.eraseConfirmation == nil else { return .none }
    state.openReason = nil
    state.isPointerInsideWindow = false
    // Every tab's request ends with the window: the next open is regular, and nothing has the focus.
    state.requests = [:]
    // The catalog is left as the window closes, so it never shows at the next open.
    if state.selectedTab.isCatalog {
      state.selectedTab = state.restoredTab
    }
    return .merge(
      .cancel(id: CancelID.hoverOpen),
      .cancel(id: CancelID.pointerLeaveClose),
      .run { _ in await window.dismiss() }
    )
  }

  /// Files dragged to the notch open the feature that takes files, without changing the remembered tab.
  private func selectDropTab(_ state: inout State) {
    guard let feature = state.fileFeature else { return }
    state.selectedTab = .feature(feature.id)
  }

  /// Files given to Vortex outside the window go to the feature that takes them; the window stays as it is. While no
  /// running feature takes files, the window opens on the page of one that would, and the files wait for it.
  private func deliver(_ urls: [URL], _ state: inout State) -> Effect<Action> {
    guard !urls.isEmpty else { return .none }
    if let feature = state.fileFeature {
      return .run { _ in await features.receiveFiles(feature.id, urls) }
    }
    guard let taker = state.catalogFeatures.first(where: { $0.acceptsFileDrops && $0.suspension == nil }) else {
      return .none
    }
    state.pendingFiles = urls
    let page = Tab.catalogPage(taker.id)
    guard !state.isOpen else {
      state.selectedTab = page
      return .none
    }
    return open(.hotkey, &state, tab: page)
  }

  /// Adds the feature, which starts on a trial, saved before it runs; its tab is the one the window opens on next.
  private func add(_ id: FeatureID, _ state: inout State) -> Effect<Action> {
    guard let feature = state.features.first(where: { $0.id == id }), !feature.isBuiltIn else { return .none }
    let before = state.runningFeatures.map(\.id)
    state.setAdded(id, true)
    state.settings.stoppedFeatures.removeAll { $0 == id }
    if state.isSafeMode { state.safeModeStarted.insert(id) }
    state.settings.lastTab = Tab.feature(id).storageValue
    beginTrials(of: state.runningFeatures.map(\.id).filter { !before.contains($0) })
    // Added back, a feature needs no Undo any more.
    guard state.removedForUndo == id else { return saveSettingsNow(state) }
    state.removedForUndo = nil
    return .merge(.cancel(id: CancelID.undoRemove), saveSettingsNow(state))
  }

  /// A window opened on the way past closes once the pointer leaves it.
  private func schedulePointerLeaveClose(_ state: State) -> Effect<Action> {
    guard state.openReason?.isPassing == true, state.settings.closeOnPointerLeave, !state.isPointerInsideWindow,
          !state.isHeldOpen
    else { return .none }
    return .run { [delay = state.settings.pointerLeaveDelay] send in
      try await clock.sleep(for: .seconds(delay))
      await send(.pointerLeaveDelayElapsed)
    }
    .cancellable(id: CancelID.pointerLeaveClose, cancelInFlight: true)
  }
}
