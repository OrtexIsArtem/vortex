import ComposableArchitecture
import Foundation
import VortexCore
import VortexPlatform

/// The app shell: when the window opens and closes, which tab it shows, and the shell's settings.
@Reducer
public struct ShellFeature: Sendable {
  @ObservableState
  public struct State: Equatable {
    public var settings: ShellSettings
    /// Every registered feature, in registry order.
    public var features: [FeatureDescriptor]
    public var selectedTab: Tab = .settings
    public var settingsSection: SettingsSection = .general
    public var isOpen = false
    public var openReason: OpenReason?
    public var isPointerInsideWindow = false
    /// Something is being dragged out of the window; it must stay open until the drop.
    public var isDraggingOut = false
    public var hasNotchedScreen = true
    public var launchAtLogin = false
    /// Language the app was started with; another choice needs a relaunch.
    public let launchLanguage: AppLanguage

    public init(settings: ShellSettings = ShellSettings(), features: [FeatureDescriptor] = []) {
      self.settings = settings
      self.features = features
      self.launchLanguage = settings.language
      self.selectedTab = restoredTab
    }

    /// All features in the user's order, enabled or not.
    public var orderedFeatures: [FeatureDescriptor] {
      let order = settings.featureOrder
      return features.enumerated()
        .sorted { lhs, rhs in
          (order.firstIndex(of: lhs.element.id) ?? order.count + lhs.offset)
            < (order.firstIndex(of: rhs.element.id) ?? order.count + rhs.offset)
        }
        .map(\.element)
    }

    /// Enabled features in sidebar order.
    public var sidebarFeatures: [FeatureDescriptor] {
      orderedFeatures.filter { !settings.disabledFeatures.contains($0.id) }
    }

    /// On displays without a notch the icon is the only way in, so it cannot be hidden there.
    public var isMenuBarIconVisible: Bool {
      settings.showMenuBarIcon || !hasNotchedScreen
    }

    public var needsRestartForLanguage: Bool {
      settings.language != launchLanguage
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

  public enum Tab: Hashable, Sendable {
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

  public enum SettingsSection: String, CaseIterable, Sendable {
    case general
    case activation
    case features
  }

  public enum Action: BindableAction, Equatable {
    case binding(BindingAction<State>)
    case task
    case window(WindowEvent)
    case hotkey(Hotkey)
    case hoverDelayElapsed
    case pointerLeaveDelayElapsed
    case tabSelected(Tab)
    case featureDropped(FeatureID, onto: FeatureID)
    case featuresMoved(fromOffsets: IndexSet, toOffset: Int)
    case featureEnabledChanged(FeatureID, isEnabled: Bool)
    case launchAtLoginChanged(Bool)
    case dragOutChanged(isDragging: Bool)
    case menuOpenTapped
    case menuSettingsTapped
    case restartButtonTapped
    case quitButtonTapped
  }

  @Dependency(\.continuousClock) var clock
  @Dependency(\.hotkeyClient) var hotkeys
  @Dependency(\.launchAtLoginClient) var launchAtLogin
  @Dependency(\.settingsClient) var settingsClient
  @Dependency(\.systemClient) var system
  @Dependency(\.windowClient) var window

  private enum CancelID {
    case hoverOpen
    case pointerLeaveClose
    case saveSettings
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    CombineReducers {
      BindingReducer()
      Reduce { state, action in
        switch action {
        case .binding:
          return .none

        case .task:
          state.launchAtLogin = launchAtLogin.isEnabled()
          if !state.settings.launchAtLoginConfigured {
            state.settings.launchAtLoginConfigured = true
            launchAtLogin.enableByDefault()
            state.launchAtLogin = launchAtLogin.isEnabled()
          }
          return .merge(
            .run { send in
              for await event in await window.events() {
                await send(.window(event))
              }
            },
            .run { send in
              for await hotkey in await hotkeys.presses() {
                await send(.hotkey(hotkey))
              }
            },
            .run { [theme = state.settings.theme] send in
              await system.applyTheme(theme)
              await send(.window(.screensChanged(hasNotch: await window.hasNotchedScreen())))
            }
          )

        case let .window(event):
          return handle(event, state: &state)

        case .hotkey(.openVortex):
          return state.isOpen ? close(&state) : open(.hotkey, &state)

        case .hoverDelayElapsed:
          guard !state.isOpen else { return .none }
          return open(.hover, &state)

        case .pointerLeaveDelayElapsed:
          guard state.isOpen, !state.isPointerInsideWindow, !state.isDraggingOut else { return .none }
          return close(&state)

        case let .tabSelected(tab):
          guard state.isAvailable(tab) else { return .none }
          state.selectedTab = tab
          state.settings.lastTab = tab.storageValue
          return .none

        case let .featureDropped(dragged, onto: target):
          var ids = state.orderedFeatures.map(\.id)
          guard dragged != target, let from = ids.firstIndex(of: dragged), ids.contains(target) else { return .none }
          let movesDown = from < ids.firstIndex(of: target)!
          ids.remove(at: from)
          let targetIndex = ids.firstIndex(of: target)!
          ids.insert(dragged, at: movesDown ? targetIndex + 1 : targetIndex)
          state.settings.featureOrder = ids
          return .none

        case let .featuresMoved(fromOffsets: source, toOffset: destination):
          var ids = state.orderedFeatures.map(\.id)
          ids.move(fromOffsets: source, toOffset: destination)
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
          return .none

        case let .launchAtLoginChanged(isEnabled):
          try? launchAtLogin.setEnabled(isEnabled)
          state.launchAtLogin = launchAtLogin.isEnabled()
          return .none

        case let .dragOutChanged(isDragging):
          state.isDraggingOut = isDragging
          return isDragging ? .cancel(id: CancelID.pointerLeaveClose) : schedulePointerLeaveClose(state)

        case .menuOpenTapped:
          return state.isOpen ? .none : open(.menuBarIcon, &state)

        case .menuSettingsTapped:
          let effect = state.isOpen ? .none : open(.menuBarIcon, &state)
          state.selectedTab = .settings
          return effect

        case .restartButtonTapped:
          return .run { [settings = state.settings] _ in
            try? await settingsClient.save(settings)
            await system.relaunch()
          }

        case .quitButtonTapped:
          return .run { [settings = state.settings] _ in
            try? await settingsClient.save(settings)
            await system.quit()
          }
        }
      }
    }
    .onChange(of: \.settings) { _, settings in
      Reduce { _, _ in
        .run { _ in
          try await clock.sleep(for: .milliseconds(400))
          try await settingsClient.save(settings)
        }
        .cancellable(id: CancelID.saveSettings, cancelInFlight: true)
      }
    }
    .onChange(of: \.settings.theme) { _, theme in
      Reduce { _, _ in
        .run { _ in await system.applyTheme(theme) }
      }
    }
    .onChange(of: \.settings.language) { _, language in
      Reduce { _, _ in
        .run { _ in system.applyLanguage(language) }
      }
    }
    .onChange(of: \.settings.showMenuBarIcon) { _, _ in
      Reduce { state, _ in
        .run { [isVisible = state.isMenuBarIconVisible] _ in await window.setMenuBarIconVisible(isVisible) }
      }
    }
  }

  private func handle(_ event: WindowEvent, state: inout State) -> Effect<Action> {
    switch event {
    case let .notchHoverChanged(isInside):
      guard isInside else { return .cancel(id: CancelID.hoverOpen) }
      guard !state.isOpen, state.settings.openOnHover else { return .none }
      return .run { [delay = state.settings.hoverDelay] send in
        try await clock.sleep(for: .seconds(delay))
        await send(.hoverDelayElapsed)
      }
      .cancellable(id: CancelID.hoverOpen, cancelInFlight: true)

    case .notchClicked:
      if state.isOpen { return close(&state) }
      guard state.settings.openOnClick else { return .none }
      return open(.click, &state)

    case .fileDragEnteredNotch:
      if state.isOpen {
        selectDropTab(&state)
        return .none
      }
      return open(.fileDrag, &state)

    case .menuBarIconClicked:
      return state.isOpen ? close(&state) : open(.menuBarIcon, &state)

    case .filesDroppedOnMenuBarIcon:
      // Files go to the feature that accepts them once one exists (the shelf, stage 2).
      return .none

    case let .pointerInsideWindowChanged(isInside):
      state.isPointerInsideWindow = isInside
      return isInside ? .cancel(id: CancelID.pointerLeaveClose) : schedulePointerLeaveClose(state)

    case .clickedOutside:
      guard state.isOpen, state.settings.closeOnClickOutside, !state.isDraggingOut else { return .none }
      return close(&state)

    case .escapePressed:
      guard state.isOpen else { return .none }
      return close(&state)

    case let .screensChanged(hasNotch):
      state.hasNotchedScreen = hasNotch
      let menuBarIcon = Effect<Action>.run { [isVisible = state.isMenuBarIconVisible] _ in
        await window.setMenuBarIconVisible(isVisible)
      }
      // The window was placed for the old screen layout.
      return state.isOpen ? .merge(close(&state), menuBarIcon) : menuBarIcon
    }
  }

  private func open(_ reason: OpenReason, _ state: inout State) -> Effect<Action> {
    state.isOpen = true
    state.openReason = reason
    state.selectedTab = state.restoredTab
    if reason == .fileDrag { selectDropTab(&state) }
    return .merge(
      .cancel(id: CancelID.hoverOpen),
      .run { _ in await window.present(reason) }
    )
  }

  private func close(_ state: inout State) -> Effect<Action> {
    state.isOpen = false
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
    guard let feature = state.sidebarFeatures.first(where: \.acceptsFileDrops) else { return }
    state.selectedTab = .feature(feature.id)
  }

  /// Closing when the pointer leaves applies only to a window opened by hovering the notch.
  private func schedulePointerLeaveClose(_ state: State) -> Effect<Action> {
    guard state.isOpen, state.openReason == .hover, state.settings.closeOnPointerLeave,
          !state.isPointerInsideWindow, !state.isDraggingOut
    else { return .none }
    return .run { [delay = state.settings.pointerLeaveDelay] send in
      try await clock.sleep(for: .seconds(delay))
      await send(.pointerLeaveDelayElapsed)
    }
    .cancellable(id: CancelID.pointerLeaveClose, cancelInFlight: true)
  }
}

extension Array {
  /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, without importing SwiftUI into the reducer.
  mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
    let moving = source.map { self[$0] }
    let insertAt = destination - source.count { $0 < destination }
    for index in source.sorted(by: >) {
      remove(at: index)
    }
    insert(contentsOf: moving, at: insertAt)
  }
}
