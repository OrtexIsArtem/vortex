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
    /// The running features' utility actions, in sidebar order, as last read: at launch once every feature has started,
    /// then whenever the running features or their order change. The shell listens for their shortcuts and runs them.
    var utilityActions: [UtilityActionInfo] = []
    /// Home's utilities dock is out: the strip at the window's right with the running utility actions, which grows the
    /// window (`WindowSize.dock`). The button again, Esc, a click outside, another tab or the window closing put it away.
    var isDockOpen = false
    /// The keys of the dock's actions' shortcuts, by action id, read as it comes out: its tooltips name them.
    var dockKeys: [String: String] = [:]
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
    /// The cover a utility shows over the window now (`WindowCover`), as keyboard cleaning's lock screen: the window
    /// stays open under it. Only the utility writes it; the shell reads it as it is, whenever it decides.
    @SharedReader(.windowCover) var windowCover
    /// The cover the shell last heard of (`windowCoverChanged`): whether it held the keyboard, for what changes as it goes.
    var shownCover: WindowCover?
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

    /// The sidebar shows the features that run and have a tab (`FeatureDescriptor.hasTab`).
    var sidebarFeatures: [FeatureDescriptor] {
      runningFeatures.filter(\.hasTab)
    }

    /// Settings › Features: the running features with something to set, in sidebar order. That is every one: a feature
    /// with a tab has its tab's shortcut, and a utility the shortcuts of its utility actions, which its page shows before
    /// the module's own settings (`makeSettings()`).
    var settingsFeatures: [FeatureDescriptor] {
      runningFeatures
    }

    /// Settings › Features as its list shows them: the features with a tab, then the utilities as a group of their own.
    var settingsGroups: (features: [FeatureDescriptor], utilities: [FeatureDescriptor]) {
      (settingsFeatures.filter(\.hasTab), settingsFeatures.filter { !$0.hasTab })
    }

    /// The running utility actions of a feature that have a shortcut, which its page in Settings › Features records first:
    /// the shell listens for them.
    func utilityShortcuts(_ id: FeatureID) -> [UtilityActionInfo] {
      utilityActions.filter { $0.feature == id && $0.shortcut != nil }
    }

    /// The buttons of Home's utilities dock: the running utility actions in catalog order, those of features with a tab
    /// first, then the utilities', each in the user's order.
    var dockActions: [UtilityActionInfo] {
      let utilities = Set(features.filter { $0.kind == .utility }.map(\.id))
      return utilityActions.filter { !utilities.contains($0.feature) } + utilityActions.filter { utilities.contains($0.feature) }
    }

    /// The permission a dock button's yellow warning names: the one its action needs, while it reads `notGranted`.
    func dockWarning(_ action: UtilityActionInfo) -> Permission? {
      guard let permission = action.permission, PermissionMark(permissionStatuses[permission]) == .warning else { return nil }
      return permission
    }

    /// Whether the feature has a page in Settings › Features; the Settings button on its catalog page shows only then.
    func hasSettingsPage(_ id: FeatureID) -> Bool {
      settingsFeatures.contains { $0.id == id }
    }

    /// The shortcut that opens Vortex on the feature's tab, which its page in Settings › Features records; nil for a
    /// feature without a tab, which has none.
    func tabShortcut(_ id: FeatureID) -> Hotkey? {
      features.contains { $0.id == id && $0.hasTab } ? .open(id) : nil
    }

    /// Whether the feature's catalog page offers Open: it is added and has a tab to open.
    func pageOffersOpen(_ id: FeatureID) -> Bool {
      guard case .added = pageState(id) else { return false }
      return features.contains { $0.id == id && $0.hasTab }
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

    /// The catalog's "Added" section: the features with a tab the user added. Utilities have a section of their own.
    var catalogAdded: [FeatureDescriptor] {
      catalogFeatures.filter { $0.hasTab && isAdded($0) }
    }

    /// The catalog's "Can add" section: the features with a tab not added, the recommended ones first.
    var catalogAvailable: [FeatureDescriptor] {
      let available = features.filter { !$0.isBuiltIn && $0.hasTab && !isAdded($0) }
      return available.filter(\.isRecommended) + available.filter { !$0.isRecommended }
    }

    /// The catalog's "Utilities" section, after the features: every utility, added or not, in the user's order, so a row
    /// stays where it is as its switch adds or removes it.
    var catalogUtilities: [FeatureDescriptor] {
      catalogFeatures.filter { $0.kind == .utility }
    }

    /// Features the catalog hasn't shown yet; one paused in this release is never new.
    var unseenFeatures: Set<FeatureID> {
      Set(catalogFeatures.filter { !settings.seenFeatures.contains($0.id) && $0.suspension == nil }.map(\.id))
    }

    /// Whether the catalog's sidebar icon has a dot: a feature or a utility is new, stopped after a crash, or waits in
    /// safe mode.
    var catalogDot: Bool {
      let running = Set(runningFeatures.map(\.id))
      return !unseenFeatures.isEmpty
        || catalogFeatures.filter(isAdded).contains { feature in
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
        // One that keeps nothing has nothing to erase: no Erase Data and no size, while its Undo shows or after.
        guard feature.keepsData else { return .available }
        if let bytes = dataSizes[id] { return .removed(dataBytes: bytes) }
        return removedForUndo == id ? .removed(dataBytes: nil) : .available
      }
      if settings.stoppedFeatures.contains(id) { return .stopped }
      if isSafeMode, !runningFeatures.contains(where: { $0.id == id }) { return .waitingInSafeMode }
      return .added(needsSetup: feature.hasOnboardingStep && !onboarding.stepsDone.contains(id))
    }

    /// The catalog needs the large window; a feature's tab has the window it asked for, or the one with the utilities
    /// dock's strip while that is out, and every other tab the regular one.
    var windowSize: WindowSize {
      if selectedTab.isCatalog { return .large }
      guard case let .feature(id) = selectedTab else { return .regular }
      return requests[id]?.size ?? (isDockOpen ? .dock : .regular)
    }

    /// How a feature's page marks a permission it needs, as the feature's settings page does: once the feature is added,
    /// the yellow mark while the permission is off, "Works after restart" once macOS granted it to the next launch.
    /// Before the feature is added, nothing: it asks for no permission yet.
    func permissionMark(_ permission: Permission, onPageOf id: FeatureID) -> PermissionMark? {
      guard pageState(id)?.isAdded == true else { return nil }
      return PermissionMark(permissionStatuses[permission])
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

    /// The user added it, whether it runs or not.
    var isAdded: Bool {
      switch self {
      case .added, .stopped, .waitingInSafeMode: true
      case .available, .removed, .paused: false
      }
    }
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
    /// The running features' utility actions, read anew.
    case utilityActionsLoaded([UtilityActionInfo])
    /// A utility action's shortcut, or a press of its button: the dock put away, the window as the action needs it, then
    /// the action.
    case utilityActionPressed(String)
    /// Home's utilities button: its strip comes out, or goes.
    case dockToggled
    /// A click on Home outside the dock's strip.
    case dockClosed
    /// The keys of the dock's actions' shortcuts, by action id, for its tooltips.
    case dockKeysLoaded([String: String])
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
    /// A utility put its cover up over the window, or took it down (`@Shared(.windowCover)`).
    case windowCoverChanged(WindowCover?)
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
    /// A utility's switch in the catalog's Utilities section: on adds it as Add does, off removes it as Remove does.
    case utilitySwitched(FeatureID, isOn: Bool)
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
    /// A feature asked for the page of a permission macOS refused while it reads granted, as keyboard cleaning after a
    /// lock macOS didn't let start: the page says to turn the switch off and on again.
    case refusedPageRequested(Permission)
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
  @Dependency(\.keyboardLockClient) var keyboardLock
  @Dependency(\.launchGuard) var launchGuard
  @Dependency(\.launchAtLoginClient) var launchAtLogin
  @Dependency(\.permissionPage) var permissionPage
  @Dependency(\.permissionsClient) var permissions
  @Dependency(\.settingsClient) var settingsClient
  @Dependency(\.systemClient) var system
  @Dependency(\.systemSettingsNamesClient) var systemSettingsNames
  @Dependency(\.windowClient) var window
  @Dependency(\.windowCovers) var windowCovers

  private enum CancelID: Hashable {
    case hoverOpen
    case pointerLeaveClose
    case saveSettings
    /// The listener for the shortcut that opens a feature's tab.
    case tabHotkey(FeatureID)
    case undoRemove
    /// Reading the running features' widgets for Home.
    case homeWidgets
    /// Reading the running features' utility actions.
    case utilityActions
    /// The listener for a utility action's shortcut, by the action's id.
    case utilityShortcut(String)
  }

  /// The newest release on GitHub. "Check for Updates" opens it in the browser: Vortex itself never goes online.
  static let latestReleaseURL = URL(string: "https://github.com/OrtexIsArtem/vortex/releases/latest")!

  var body: some ReducerOf<Self> {
    CombineReducers {
      BindingReducer()
      Scope(state: \.onboarding, action: \.onboarding) {
        OnboardingFeature()
      }
      Reduce { state, action in
        switch action {
        case .binding:
          return .none

        case let .windowCoverChanged(cover):
          let old = state.shownCover
          guard cover != old else { return .none }
          state.shownCover = cover
          var effects: [Effect<Action>] = []
          let wasHeld = old?.holdsKeyboard == true
          let isHeld = cover?.holdsKeyboard == true
          if wasHeld != isHeld {
            // Vortex in front taking every key, or the keys back to the app that was in front.
            effects.append(.run { _ in await window.holdKeyboard(isHeld) })
          }
          guard cover == nil else {
            // A cover never shows over nothing: one that comes while the window is closed opens it, as an action that
            // needs the window open does.
            if !state.isOpen { effects.append(open(.hotkey, &state)) }
            return .merge(effects)
          }
          // The cover went, however it ended: the window closes with it, and a required permission that went meanwhile
          // blocks Vortex only now.
          effects.append(close(&state))
          if state.isBlocked { effects.append(.send(.onboarding(.blocked))) }
          return .merge(effects)

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
          let tabbed = state.runningFeatures.filter(\.hasTab).map(\.id)
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
            // A feature without a tab has no shortcut to open one.
            .merge(tabbed.map(listenForTabHotkey)),
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
              tellHome(running, current: nil),
              readUtilityActions(running, current: [])
            ),
            .run { send in
              for await statuses in permissions.updates() {
                await send(.permissionStatusesChanged(statuses))
              }
            },
            .run { send in
              for await request in permissionPage.requests() {
                switch request {
                case let .page(permission): await send(.permissionPageRequested(permission))
                case let .refused(permission): await send(.refusedPageRequested(permission))
                }
              }
            },
            // A utility's cover, each time it puts it up or takes it down.
            .run { send in
              for await cover in await windowCovers.changes() {
                await send(.windowCoverChanged(cover))
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
          // A click in the sidebar is a click outside the dock's strip, whatever it chooses.
          state.isDockOpen = false
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

        case let .utilityActionsLoaded(actions):
          let old = state.utilityActions
          state.utilityActions = actions
          // The strip goes with its last button.
          if state.dockActions.isEmpty { state.isDockOpen = false }
          // Each shortcut is listened for while its action is there: an action that went frees its keys; a new or changed
          // one listens, in place of what listened for it before.
          let gone = old.filter { action in !actions.contains { $0.id == action.id } }
          let new = actions.filter { !old.contains($0) }
          return .merge(
            .merge(gone.map { .cancel(id: CancelID.utilityShortcut($0.id)) }),
            .merge(new.map(listenForUtilityShortcut))
          )

        case let .utilityActionPressed(id):
          // Only a running feature's action: one that stopped, or never ran, does nothing.
          guard let action = state.utilityActions.first(where: { $0.id == id }) else { return .none }
          // Chosen in the dock or by its shortcut, the strip goes first.
          state.isDockOpen = false
          let perform = Effect<Action>.run { _ in await features.performUtilityAction(action.feature, id) }
          switch action.window {
          case .unchanged:
            return perform
          case .closed:
            guard state.isOpen else { return perform }
            // The window can't go while a utility's cover or the erase question holds it, so nothing runs.
            guard state.windowCover == nil, state.eraseConfirmation == nil else { return .none }
            // The window goes first: what the action shows on the screen never sits over or behind it.
            return .concatenate(close(&state), perform)
          case .open:
            guard !state.isOpen else { return perform }
            let opening = open(.hotkey, &state)
            // Blocked, or waiting for the first status read, the window doesn't open, and the action doesn't run.
            guard state.isOpen else { return opening }
            return .concatenate(opening, perform)
          }

        case .dockToggled:
          if state.isDockOpen {
            state.isDockOpen = false
            return .none
          }
          // Only in the open window, on a tab, with something to offer, and while no tab holds the focus, as Home's
          // editor does.
          guard state.isOpen, case .feature = state.selectedTab, state.focusedFeature == nil, !state.dockActions.isEmpty
          else { return .none }
          state.isDockOpen = true
          // Growing the window is deliberate, as a tab's request is: it no longer closes when the pointer leaves it.
          state.openReason = .click
          return .merge(.cancel(id: CancelID.pointerLeaveClose), readDockKeys(state.dockActions))

        case .dockClosed:
          state.isDockOpen = false
          return .none

        case let .dockKeysLoaded(keys):
          state.dockKeys = keys
          return .none

        case let .windowRequested(id, request):
          // Only while the window is open: a tab left mounted behind the closed window can't make the next open large.
          guard state.isOpen else { return .none }
          state.requests[id] = request == .regular ? nil : request
          // Growing or taking the focus is deliberate, as going to the catalog is: the window no longer closes when the
          // pointer leaves it.
          guard request != .regular else { return .none }
          // The tab's own size takes the place of the dock's strip, as Home's editor does after the dock's pencil.
          state.isDockOpen = false
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
          return remove(id, &state)

        case let .utilitySwitched(id, isOn):
          // Only a utility has a switch, and a paused one shows it off and still.
          guard let feature = state.features.first(where: { $0.id == id }), feature.kind == .utility, !feature.isBuiltIn,
                feature.suspension == nil, state.isAdded(feature) != isOn
          else { return .none }
          guard isOn else { return remove(id, &state) }
          let effect = add(id, &state)
          // Its own setup shows on its page, under its buttons, as after Add there.
          if feature.hasOnboardingStep, !state.onboarding.stepsDone.contains(id) {
            state.selectedTab = .catalogPage(id)
          }
          return effect

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
          // Only a feature that isn't added and keeps something has data to erase from its page.
          guard let feature = state.features.first(where: { $0.id == id }), !feature.isBuiltIn, !state.isAdded(feature),
                feature.keepsData
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
          // The page opens in the onboarding's window; the notch window closes first, except under a cover.
          return .merge(close(&state), .send(.onboarding(.pageRequested(permission, .request))))

        case let .refusedPageRequested(permission):
          // As any page, its words aside; it doesn't close by itself on a grant.
          return .merge(close(&state), .send(.onboarding(.pageRequested(permission, .lockRefused))))
        }
      }
    }
    .onChange(of: \.blockState) { old, new in
      Reduce { state, _ in
        state.$appBlocked.withLock { $0 = new.isBlocked }
        // Becoming blocked after the launch's read, however it happened: the notch window closes and the blocking page
        // opens. Under a utility's cover this waits for the cover to go.
        guard new.isBlocked, !old.isBlocked, old.isRead, state.windowCover == nil else { return .none }
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
        .merge(
          syncRunning(from: old, to: new, &state),
          .concatenate(
            tellHome(new.map(\.id), current: state.homeWidgets ?? []),
            readUtilityActions(new.map(\.id), current: state.utilityActions)
          )
        )
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
        // The dock's strip is Home's: it goes as Home's tab is left, however it is.
        state.isDockOpen = false
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
    let startedTabs = new.filter { started.contains($0.id) && $0.hasTab }.map(\.id)
    return .merge(
      .merge(cancellations),
      .merge(startedTabs.map(listenForTabHotkey)),
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

  /// Reads the running features' utility actions, and tells them unless they are `current`. The newest read wins.
  private func readUtilityActions(_ running: [FeatureID], current: [UtilityActionInfo]) -> Effect<Action> {
    .run { send in
      let actions = await features.utilityActions(running)
      if actions != current { await send(.utilityActionsLoaded(actions)) }
    }
    .cancellable(id: CancelID.utilityActions, cancelInFlight: true)
  }

  /// Reads the keys of the dock's actions' shortcuts for its tooltips, as the strip comes out: the user may have recorded
  /// them since.
  private func readDockKeys(_ actions: [UtilityActionInfo]) -> Effect<Action> {
    .run { send in
      var keys: [String: String] = [:]
      for action in actions {
        guard let name = action.shortcut, let shortcut = await hotkeys.shortcut(Hotkey(name)) else { continue }
        keys[action.id] = shortcut
      }
      await send(.dockKeysLoaded(keys))
    }
  }

  /// Listens for a utility action's shortcut, if it has one, while the action is there; cancelling it frees the keys. A
  /// press runs the action as a click does.
  private func listenForUtilityShortcut(_ action: UtilityActionInfo) -> Effect<Action> {
    guard let name = action.shortcut else { return .none }
    return .run { send in
      for await _ in hotkeys.presses(Hotkey(name)) {
        await send(.utilityActionPressed(action.id))
      }
    }
    .cancellable(id: CancelID.utilityShortcut(action.id), cancelInFlight: true)
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
      // The dock's strip goes with any click outside it, even where the window stays.
      state.isDockOpen = false
      guard state.isOpen, state.settings.closeOnClickOutside, !state.isHeldOpen else { return .none }
      return close(&state)

    case .escapePressed:
      guard state.isOpen else { return .none }
      // Esc answers the erase question with Cancel.
      if state.eraseConfirmation != nil {
        state.eraseConfirmation = nil
        return .none
      }
      // Then it puts the dock's strip away, and the window stays.
      if state.isDockOpen {
        state.isDockOpen = false
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
      // A window kept open under a utility's cover moves to the new screens; any other was placed for the old ones.
      return state.windowCover != nil ? .run { _ in await window.present(reason) } : close(&state)

    case let .keyPressedWhileHeld(key):
      // The key went nowhere, but it reaches the lock's presses as if the lock had held it back: keyboard cleaning's
      // lock screen washes it.
      return .run { _ in await keyboardLock.reportPassed(key) }
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
    // A utility's cover keeps the window open until it goes, as keyboard cleaning's until the user turns the keyboard
    // back on, and the erase question until the user answers it.
    guard state.windowCover == nil, state.eraseConfirmation == nil else { return .none }
    state.openReason = nil
    state.isPointerInsideWindow = false
    // Every tab's request ends with the window, and so does the dock's strip: the next open is regular, and nothing has
    // the focus.
    state.requests = [:]
    state.isDockOpen = false
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

  /// Adds the feature, which starts on a trial, saved before it runs; its tab, if it has one, is the one the window
  /// opens on next.
  private func add(_ id: FeatureID, _ state: inout State) -> Effect<Action> {
    guard let feature = state.features.first(where: { $0.id == id }), !feature.isBuiltIn else { return .none }
    let before = state.runningFeatures.map(\.id)
    state.setAdded(id, true)
    state.settings.stoppedFeatures.removeAll { $0 == id }
    if state.isSafeMode { state.safeModeStarted.insert(id) }
    if feature.hasTab { state.settings.lastTab = Tab.feature(id).storageValue }
    beginTrials(of: state.runningFeatures.map(\.id).filter { !before.contains($0) })
    // Added back, a feature needs no Undo any more.
    guard state.removedForUndo == id else { return saveSettingsNow(state) }
    state.removedForUndo = nil
    return .merge(.cancel(id: CancelID.undoRemove), saveSettingsNow(state))
  }

  /// Removes the feature, which stops, saved at once; Undo shows for 5 s. Its data stays until Erase Data.
  private func remove(_ id: FeatureID, _ state: inout State) -> Effect<Action> {
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
