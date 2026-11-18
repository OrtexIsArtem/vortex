import ComposableArchitecture
import Foundation
import Testing
import VortexCore

@testable import VortexShell

/// Settings › Features: a list of the running features, each opening its own page with its tab's shortcut and its own
/// settings.
@MainActor
struct SettingsFeaturesTests {
  let shell = ShellFeatureTests()

  /// Clicks Settings in the sidebar, then the Features segment.
  func showFeatures(_ store: TestStoreOf<ShellFeature>) async {
    await store.send(.tabSelected(.settings)) {
      $0.selectedTab = .settings
      $0.settings.lastTab = "settings"
    }
    await store.send(.binding(.set(\.settingsSection, .features))) { $0.settingsSection = .features }
  }

  // MARK: - The list

  /// Every running feature has at least its tab's shortcut to set, so the list holds each one, in sidebar order. A
  /// feature not added, stopped after a crash, paused or waiting in safe mode has no page.
  @Test
  func theListHoldsTheRunningFeaturesInSidebarOrder() {
    let paused = FeatureDescriptor(id: "music", title: "Music", symbol: "music.note", suspension: "Broken on this macOS.")
    let features: [FeatureDescriptor] = [.home, .timer, .shelf, .tasks, .secrets, paused]
    var settings = ShellSettings()
    settings.addedFeatures = ["home", "timer", "tasks", "secrets", "music"]
    settings.featureOrder = ["tasks", "home", "timer"]
    settings.stoppedFeatures = ["secrets"]
    let state = ShellFeature.State(settings: settings, features: features, onboarding: .finished)
    #expect(state.settingsFeatures.map(\.id) == ["tasks", "home", "timer"])
    #expect(state.hasSettingsPage("tasks"))
    #expect(state.hasSettingsPage("home"))
    #expect(!state.hasSettingsPage("shelf"))
    #expect(!state.hasSettingsPage("secrets"))
    #expect(!state.hasSettingsPage("music"))
    #expect(!state.hasSettingsPage("gone"))

    let safeMode = ShellFeature.State(settings: settings, features: features, onboarding: .finished, isSafeMode: true)
    #expect(safeMode.settingsFeatures.map(\.id) == ["home"])
  }

  /// A row has the yellow dot of its feature's sidebar icon, as both ask the same: the first permission the feature
  /// needs that reads `notGranted`; none before the first read, and none for one that works after a restart.
  @Test
  func aRowHasTheYellowDotOfItsSidebarIcon() {
    let timer = FeatureDescriptor(
      id: "timer", title: "Timer", symbol: "timer",
      permissionNeeds: [PermissionNeed(.notifications, reason: "Tells you when a timer ends.")]
    )
    let tasks = FeatureDescriptor(
      id: "tasks", title: "Tasks", symbol: "checklist",
      permissionNeeds: [
        PermissionNeed(.screenRecording, reason: "Turns a screenshot into a new task."),
        PermissionNeed(.notifications, reason: "Tells you about a task."),
      ]
    )
    let state = ShellFeature.State(features: [.home, timer, tasks], onboarding: .finished)
    func dots() -> [Permission?] { state.settingsFeatures.map { state.permissionOff(for: $0) } }
    #expect(state.settingsFeatures.map(\.id) == ["home", "timer", "tasks"])
    #expect(dots() == [nil, nil, nil])
    state.$permissionStatuses.withLock { $0 = [.notifications: .notGranted, .screenRecording: .grantedAfterRestart] }
    #expect(dots() == [nil, .notifications, .notifications])
    state.$permissionStatuses.withLock { $0 = [.notifications: .notGranted, .screenRecording: .notGranted] }
    #expect(dots() == [nil, .notifications, .screenRecording])
    state.$permissionStatuses.withLock { $0 = [.notifications: .granted, .screenRecording: .granted] }
    #expect(dots() == [nil, nil, nil])
  }

  /// An added feature that doesn't run yet, as before the user chooses features, has nothing to set: its catalog page
  /// hides Settings, and neither that button nor a row opens a page for it.
  @Test
  func aFeatureThatDoesntRunHasNoPageAndNoSettingsButton() async {
    let store = shell.makeStore(features: [.home, .timer]) { $0.featuresChosen = false }
    #expect(store.state.pageState("timer") == .added(needsSetup: false))
    #expect(!store.state.hasSettingsPage("timer"))
    #expect(store.state.hasSettingsPage("home"))
    await store.send(.featureSettingsTapped("timer"))
    await store.send(.settingsRowTapped("timer"))
    await store.send(.settingsRowTapped("gone"))
  }

  // MARK: - A feature's page

  /// Settings on a feature's catalog page goes straight to that feature's page in Settings › Features, in the regular
  /// window; Settings is then the tab the window opens on.
  @Test
  func theCatalogsSettingsButtonOpensTheFeaturesPage() async {
    let store = shell.makeStore()
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalogPage("shelf"))) {
      $0.selectedTab = .catalogPage("shelf")
      $0.openReason = .click
    }
    await store.send(.featureSettingsTapped("shelf")) {
      $0.selectedTab = .settings
      $0.settings.lastTab = "settings"
      $0.settingsSection = .features
      $0.settingsFeature = "shelf"
    }
    #expect(store.state.settingsPage?.id == "shelf")
    await shell.clock.advance(by: .milliseconds(400))
    #expect(shell.windowLog.value == ["size:regular", "present:hover", "size:large", "size:regular"])
    #expect(shell.dismissals.value == 0)
  }

  /// "‹ Features" and Esc go from a page back to the list, as on the catalog's pages; on the list Esc closes the
  /// window, as before.
  @Test
  func backAndEscapeGoFromAPageBackToTheList() async {
    let store = shell.makeStore()
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = .click }
    await showFeatures(store)
    #expect(store.state.settingsPage == nil)
    await store.send(.settingsRowTapped("timer")) { $0.settingsFeature = "timer" }
    #expect(store.state.settingsPage?.id == "timer")
    await store.send(.settingsBackTapped) { $0.settingsFeature = nil }
    await store.send(.settingsRowTapped("tasks")) { $0.settingsFeature = "tasks" }
    await store.send(.window(.escapePressed)) { $0.settingsFeature = nil }
    #expect(shell.dismissals.value == 0)
    await store.send(.window(.escapePressed)) { $0.openReason = nil }
    #expect(shell.dismissals.value == 1)
    await shell.clock.advance(by: .milliseconds(400))
  }

  /// The page shows only in the Features segment: on another one Esc closes the window as before, and the page is still
  /// there once the user comes back to Features.
  @Test
  func onAnotherSegmentEscapeClosesAndThePageWaits() async {
    let store = shell.makeStore()
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = .click }
    await showFeatures(store)
    await store.send(.settingsRowTapped("timer")) { $0.settingsFeature = "timer" }
    await store.send(.binding(.set(\.settingsSection, .general))) { $0.settingsSection = .general }
    await store.send(.window(.escapePressed)) { $0.openReason = nil }
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = .click }
    await store.send(.binding(.set(\.settingsSection, .features))) { $0.settingsSection = .features }
    #expect(store.state.settingsPage?.id == "timer")
    await shell.clock.advance(by: .milliseconds(400))
  }

  /// Settings remembers the open page while the app runs, as it remembers the segment: the window opens on it again.
  @Test
  func theOpenPageStaysWhenTheWindowClosesAndOpens() async {
    let store = shell.makeStore()
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = .click }
    await showFeatures(store)
    await store.send(.settingsRowTapped("shelf")) { $0.settingsFeature = "shelf" }
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = nil }
    await store.send(.openHotkeyPressed) { $0.openReason = .hotkey }
    #expect(store.state.selectedTab == .settings)
    #expect(store.state.settingsSection == .features)
    #expect(store.state.settingsPage?.id == "shelf")
    await shell.clock.advance(by: .milliseconds(400))
  }

  /// A feature that stops while its page is open, as when it is removed from the sidebar's menu, leaves the list
  /// showing; another feature that stops leaves the page as it is.
  @Test
  func aFeatureThatStopsWhileItsPageIsOpenLeavesTheList() async {
    let store = shell.makeStore()
    await showFeatures(store)
    await store.send(.settingsRowTapped("timer")) { $0.settingsFeature = "timer" }
    await store.send(.featureRemoved("tasks")) {
      $0.settings.addedFeatures = ["timer", "shelf"]
      $0.removedForUndo = "tasks"
    }
    await store.send(.featureRemoved("timer")) {
      $0.settings.addedFeatures = ["shelf"]
      $0.removedForUndo = "timer"
      $0.settingsFeature = nil
    }
    #expect(store.state.selectedTab == .settings)
    await shell.clock.advance(by: .seconds(5))
    await store.receive(\.undoExpired) { $0.removedForUndo = nil }
    await store.finish()
    #expect(shell.featureSwitches.value == ["tasks:false", "timer:false"])
  }
}
