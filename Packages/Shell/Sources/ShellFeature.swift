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
    /// Why the window is open; nil while it is closed.
    var openReason: OpenReason?
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
    var launchAtLogin: LaunchAtLoginStatus = .disabled
    var language: AppLanguage
    /// Language the app was started with; another choice needs a relaunch.
    let launchLanguage: AppLanguage
    /// What macOS says about each permission, as last read (S1); empty until the first read. Only the shell writes it.
    @Shared(.permissionStatuses) var permissionStatuses
    /// A required permission that something enabled needs reads `notGranted` (S9); follows `isBlocked`.
    @Shared(.appBlocked) var appBlocked
    /// The permissions Vortex can't be used without; QA mode may change them per run (S30).
    var requiredPermissions = OnboardingConfig.requiredPermissions

    init(settings: ShellSettings = ShellSettings(), features: [FeatureDescriptor] = [], language: AppLanguage = .system) {
      self.settings = settings
      self.features = features
      self.language = language
      self.launchLanguage = language
      self.selectedTab = restoredTab
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

    /// Enabled features in sidebar order.
    var sidebarFeatures: [FeatureDescriptor] {
      orderedFeatures.filter { !settings.disabledFeatures.contains($0.id) }
    }

    /// The icon is the only way in while some display has no notch, or while the notch can't open Vortex.
    var isMenuBarIconRequired: Bool {
      !everyScreenHasNotch || !(settings.openOnHover || settings.openOnClick)
    }

    var isMenuBarIconVisible: Bool {
      settings.showMenuBarIcon || isMenuBarIconRequired
    }

    /// The enabled feature that gets files given to Vortex, see `FeatureModule.acceptsFileDrops`.
    var fileFeature: FeatureDescriptor? {
      sidebarFeatures.first(where: \.acceptsFileDrops)
    }

    var needsRestartForLanguage: Bool {
      language != launchLanguage
    }

    /// The permissions the enabled features and the shell need now, and why.
    var permissionCatalog: PermissionCatalog {
      PermissionCatalog(features: sidebarFeatures, required: requiredPermissions)
    }

    /// A required permission that something enabled needs reads `notGranted`; never before the first read (S9, S66).
    /// Checked after every action, so with nothing required it builds no catalog.
    var isBlocked: Bool {
      !requiredPermissions.isEmpty && !permissionCatalog.missingRequired(permissionStatuses).isEmpty
    }

    /// The last tab the user chose if it still exists; otherwise the first feature, then settings.
    var restoredTab: Tab {
      if let last = settings.lastTab.map(Tab.init(storageValue:)), isAvailable(last) {
        return last
      }
      return sidebarFeatures.first.map { .feature($0.id) } ?? .settings
    }

    func isAvailable(_ tab: Tab) -> Bool {
      switch tab {
      case .settings: true
      case let .feature(id): sidebarFeatures.contains { $0.id == id }
      }
    }
  }

  enum Tab: Hashable, Sendable {
    case feature(FeatureID)
    case settings

    var storageValue: String {
      switch self {
      case let .feature(id): "feature:\(id)"
      case .settings: "settings"
      }
    }

    init(storageValue: String) {
      self = storageValue.hasPrefix("feature:") ? .feature(String(storageValue.dropFirst("feature:".count))) : .settings
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
    case featureDropped(FeatureID, onto: FeatureID)
    case featureEnabledChanged(FeatureID, isEnabled: Bool)
    case settingsShown
    case launchAtLoginChanged(Bool)
    case launchAtLoginStatusLoaded(LaunchAtLoginStatus)
    case openLoginItemsTapped
    case menuOpenTapped
    case menuSettingsTapped
    case restartButtonTapped
    case quitButtonTapped
    case keyboardCleaning(KeyboardCleaningFeature.Action)
    /// macOS's statuses, at the first read and on every change (S3).
    case permissionStatusesChanged([Permission: PermissionStatus])
    /// A feature asked for the page of one permission (S24).
    case permissionPageRequested(Permission)
  }

  @Dependency(\.continuousClock) var clock
  @Dependency(\.featuresClient) var features
  @Dependency(\.hotkeyClient) var hotkeys
  @Dependency(\.launchAtLoginClient) var launchAtLogin
  @Dependency(\.permissionPage) var permissionPage
  @Dependency(\.permissionsClient) var permissions
  @Dependency(\.settingsClient) var settingsClient
  @Dependency(\.systemClient) var system
  @Dependency(\.windowClient) var window

  private enum CancelID {
    case hoverOpen
    case pointerLeaveClose
    case saveSettings
  }

  var body: some ReducerOf<Self> {
    CombineReducers {
      BindingReducer()
      Scope(state: \.keyboardCleaning, action: \.keyboardCleaning) {
        KeyboardCleaningFeature()
      }
      Reduce { state, action in
        switch action {
        case .binding:
          return .none

        case .keyboardCleaning(.stopTapped):
          // The keyboard is back on: the window closes, and the keys go back to the app the user was in.
          return close(&state)

        case .keyboardCleaning:
          return .none

        case .task:
          let featureSwitches = state.orderedFeatures.map { ($0.id, !state.settings.disabledFeatures.contains($0.id)) }
          return .merge(
            .run { [isVisible = state.isMenuBarIconVisible, acceptsFiles = state.fileFeature != nil] send in
              await window.setMenuBarIconVisible(isVisible)
              await window.setAcceptsFiles(acceptsFiles)
              for await event in await window.events() {
                await send(.window(event))
              }
            },
            .run { send in
              for await _ in hotkeys.presses(.openVortex) {
                await send(.openHotkeyPressed)
              }
            },
            .merge(state.features.map { feature in
              .run { send in
                for await _ in hotkeys.presses(.open(feature.id)) {
                  await send(.featureHotkeyPressed(feature.id))
                }
              }
            }),
            .run { [theme = state.settings.theme] send in
              await system.applyTheme(theme)
              for (id, isEnabled) in featureSwitches {
                await features.setEnabled(id, isEnabled)
              }
              await launchAtLogin.enableOnFirstLaunch()
              await send(.launchAtLoginStatusLoaded(launchAtLogin.status()))
            },
            .run { send in
              for await statuses in permissions.updates() {
                await send(.permissionStatusesChanged(statuses))
              }
            },
            .run { send in
              for await permission in permissionPage.requests() {
                await send(.permissionPageRequested(permission))
              }
            }
          )

        case let .window(event):
          return handle(event, state: &state)

        case .openHotkeyPressed:
          return state.isOpen ? close(&state) : open(.hotkey, &state)

        case let .featureHotkeyPressed(id):
          let tab = Tab.feature(id)
          guard state.isAvailable(tab) else { return .none }
          if state.isOpen, state.selectedTab == tab { return close(&state) }
          let effect = state.isOpen ? .none : open(.hotkey, &state)
          state.selectedTab = tab
          state.settings.lastTab = tab.storageValue
          return effect

        case let .filesReceived(urls):
          return deliver(urls, state)

        case .hoverDelayElapsed:
          guard !state.isOpen else { return .none }
          // What counts is where the pointer is now, when the delay ends.
          return open(.hover, onEarOf: state.hoveredEar, &state)

        case .pointerLeaveDelayElapsed:
          guard state.isOpen, !state.isPointerInsideWindow, !state.isHeldOpen else { return .none }
          return close(&state)

        case let .tabSelected(tab):
          guard state.isAvailable(tab) else { return .none }
          state.selectedTab = tab
          state.settings.lastTab = tab.storageValue
          return .none

        case let .featureDropped(dragged, onto: target):
          var ids = state.orderedFeatures.map(\.id)
          guard let from = ids.firstIndex(of: dragged), let to = ids.firstIndex(of: target), from != to else { return .none }
          ids.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
          state.settings.featureOrder = ids
          return .none

        case let .featureEnabledChanged(id, isEnabled):
          if isEnabled {
            state.settings.disabledFeatures.removeAll { $0 == id }
          } else if !state.settings.disabledFeatures.contains(id) {
            state.settings.disabledFeatures.append(id)
          }
          if !state.isAvailable(state.selectedTab) {
            state.selectedTab = state.restoredTab
          }
          return .run { _ in await features.setEnabled(id, isEnabled) }

        case .settingsShown:
          // The user may have changed the login item in System Settings meanwhile.
          return .run { send in await send(.launchAtLoginStatusLoaded(launchAtLogin.status())) }

        case let .launchAtLoginChanged(isEnabled):
          return .run { send in await send(.launchAtLoginStatusLoaded(launchAtLogin.setEnabled(isEnabled))) }

        case let .launchAtLoginStatusLoaded(status):
          state.launchAtLogin = status
          return .none

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

        case let .permissionStatusesChanged(statuses):
          state.$permissionStatuses.withLock { $0 = statuses }
          return .none

        case let .permissionPageRequested(permission):
          // For now macOS is asked at once; the onboarding window will show the permission's page instead.
          return .run { _ in await permissions.request(permission) }
        }
      }
    }
    .onChange(of: \.isBlocked) { _, isBlocked in
      Reduce { state, _ in
        state.$appBlocked.withLock { $0 = isBlocked }
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
      return deliver(urls, state)

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
      return close(&state)

    case let .screensChanged(everyScreenHasNotch):
      state.everyScreenHasNotch = everyScreenHasNotch
      guard let reason = state.openReason else { return .none }
      // A window kept open for keyboard cleaning moves to the new screens; any other was placed for the old ones.
      return state.keyboardCleaning.isLocked ? .run { _ in await window.present(reason) } : close(&state)
    }
  }

  private func open(_ reason: OpenReason, _ state: inout State) -> Effect<Action> {
    state.openReason = reason
    state.selectedTab = state.restoredTab
    if reason == .fileDrag { selectDropTab(&state) }
    return .merge(
      .cancel(id: CancelID.hoverOpen),
      .run { _ in await window.present(reason) },
      // Notifications send no signal when they change, and the window opening activates no app: read again (S47).
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
    // Keyboard cleaning keeps the window open until the user turns the keyboard back on.
    guard !state.keyboardCleaning.isLocked else { return .none }
    state.openReason = nil
    state.isPointerInsideWindow = false
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

  /// Files given to Vortex outside the window go to the feature that takes them; the window stays as it is.
  private func deliver(_ urls: [URL], _ state: State) -> Effect<Action> {
    guard let feature = state.fileFeature, !urls.isEmpty else { return .none }
    return .run { _ in await features.receiveFiles(feature.id, urls) }
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
