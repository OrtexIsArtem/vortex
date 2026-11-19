import ComposableArchitecture
import Foundation
import Testing
import VortexCore

@testable import VortexShell

extension FeatureDescriptor {
  /// A recommended utility, as keyboard cleaning.
  static let cleaning = FeatureDescriptor(
    id: "keyboard", title: "Keyboard Cleaning", symbol: "keyboard", kind: .utility,
    permissionNeeds: [PermissionNeed(.accessibility, reason: "Locks the keyboard while you clean it.")],
    isRecommended: true
  )
}

/// Utilities in the catalog, in Settings › Features and on the onboarding's Features page: a group of their own, after
/// the features. In the catalog each row has a switch that adds or removes the utility, by Add and Remove's rules.
@MainActor
struct UtilitiesCatalogTests {
  let shell = ShellFeatureTests()

  // MARK: - The catalog

  /// Added and Can add hold the features with a tab; Utilities, after them, holds every utility, added or not, in the
  /// user's order, so a row stays where it is as its switch flips.
  @Test
  func theCatalogListsTheUtilitiesInASectionOfTheirOwnAfterTheFeatures() {
    var settings = ShellSettings()
    settings.addedFeatures = ["home", "timer", "screentext"]
    let state = ShellFeature.State(settings: settings, features: [.home, .timer, .tasks, .screenText, .cleaning])
    #expect(state.catalogAdded.map(\.id) == ["timer"])
    #expect(state.catalogAvailable.map(\.id) == ["tasks"])
    #expect(state.catalogUtilities.map(\.id) == ["screentext", "keyboard"])
    #expect(state.catalogUtilities.map { state.isAdded($0) } == [true, false])
  }

  /// A utility stopped after a crash lights the catalog's dot, as a feature does.
  @Test
  func aStoppedUtilityLightsTheDot() {
    var settings = ShellSettings()
    settings.addedFeatures = ["home", "screentext"]
    settings.seenFeatures = ["home", "screentext"]
    #expect(!ShellFeature.State(settings: settings, features: [.home, .screenText]).catalogDot)
    settings.stoppedFeatures = ["screentext"]
    #expect(ShellFeature.State(settings: settings, features: [.home, .screenText]).catalogDot)
  }

  /// The row's switch adds the utility as Add does, on a trial and saved at once, and the list stays in view; off, it
  /// removes it as Remove does, with Undo for 5 s. A feature with a tab, or a paused utility, has no switch.
  @Test
  func theSwitchAddsAndRemovesAUtilityWithUndo() async {
    let paused = FeatureDescriptor(
      id: "ruler", title: "Ruler", symbol: "ruler", kind: .utility, suspension: "Broken on this macOS."
    )
    let store = shell.makeStore(features: [.home, .timer, .screenText, paused]) {
      $0.addedFeatures = ["home", "timer"]
      $0.seenFeatures = ["home", "timer", "screentext", "ruler"]
      $0.lastTab = "feature:timer"
    }
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalog)) {
      $0.selectedTab = .catalog
      $0.openReason = .click
    }
    await store.send(.utilitySwitched("screentext", isOn: true)) {
      $0.settings.addedFeatures = ["home", "timer", "screentext"]
    }
    #expect(shell.saved.value.last?.addedFeatures == ["home", "timer", "screentext"])
    #expect(shell.trials.value == ["screentext"])
    await store.send(.utilitySwitched("screentext", isOn: false)) {
      $0.settings.addedFeatures = ["home", "timer"]
      $0.removedForUndo = "screentext"
    }
    await store.send(.undoRemoveTapped) {
      $0.settings.addedFeatures = ["home", "timer", "screentext"]
      $0.removedForUndo = nil
    }
    // Nothing for a feature with a tab, a paused utility, or a switch that already says so.
    await store.send(.utilitySwitched("timer", isOn: false))
    await store.send(.utilitySwitched("ruler", isOn: true))
    await store.send(.utilitySwitched("screentext", isOn: true))
    await shell.clock.advance(by: .milliseconds(400))
    await store.finish()
    #expect(shell.featureSwitches.value == ["screentext:true", "screentext:false", "screentext:true"])
    #expect(store.state.selectedTab == .catalog)
    #expect(store.state.settings.lastTab == "feature:timer")
  }

  /// A utility whose own setup isn't done goes to its page as its switch adds it, where the setup shows under its
  /// buttons, as after Add there.
  @Test
  func addingAUtilityThatNeedsSetupOpensItsPage() async {
    let ruler = FeatureDescriptor(id: "ruler", title: "Ruler", symbol: "ruler", kind: .utility, hasOnboardingStep: true)
    let store = shell.makeStore(features: [.home, ruler]) {
      $0.addedFeatures = ["home"]
      $0.seenFeatures = ["home", "ruler"]
    }
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalog)) {
      $0.selectedTab = .catalog
      $0.openReason = .click
    }
    await store.send(.utilitySwitched("ruler", isOn: true)) {
      $0.settings.addedFeatures = ["home", "ruler"]
      $0.selectedTab = .catalogPage("ruler")
    }
    #expect(store.state.pageState("ruler") == .added(needsSetup: true))
    await shell.clock.advance(by: .milliseconds(400))
    await store.finish()
  }

  // MARK: - Settings › Features

  /// Settings › Features lists the running features first, then the running utilities as a group of their own, each in
  /// the user's order.
  @Test
  func settingsListsTheRunningUtilitiesAfterTheFeatures() {
    var settings = ShellSettings()
    settings.addedFeatures = ["home", "timer", "screentext", "keyboard"]
    settings.featureOrder = ["screentext", "timer"]
    let state = ShellFeature.State(
      settings: settings, features: [.home, .timer, .tasks, .screenText, .cleaning], onboarding: .finished
    )
    #expect(state.settingsGroups.features.map(\.id) == ["timer", "home"])
    #expect(state.settingsGroups.utilities.map(\.id) == ["screentext", "keyboard"])
    #expect(state.hasSettingsPage("keyboard") && state.hasSettingsPage("timer"))
    #expect(!state.hasSettingsPage("tasks"))
  }

  /// A utility's page shows the shortcuts of its utility actions, which the shell listens for, before its own
  /// settings; it has no tab's shortcut.
  @Test
  func aUtilitysPageShowsItsActionsShortcuts() {
    var settings = ShellSettings()
    settings.addedFeatures = ["home", "screentext", "keyboard"]
    var state = ShellFeature.State(settings: settings, features: [.home, .screenText, .cleaning], onboarding: .finished)
    state.utilityActions = [
      UtilityActionInfo(id: "screentext.copy", feature: "screentext", window: .closed, shortcut: "copyScreenText"),
      UtilityActionInfo(id: "keyboard.lock", feature: "keyboard", window: .open),
    ]
    #expect(state.tabShortcut("screentext") == nil)
    #expect(state.utilityShortcuts("screentext").map(\.id) == ["screentext.copy"])
    #expect(state.utilityShortcuts("keyboard").isEmpty)
  }

  // MARK: - The onboarding's Features page

  /// The Features page lists the utilities as a group of their own, after the features, with the recommended ones
  /// checked as a fresh install adds them.
  @Test
  func theFeaturesPageListsTheUtilitiesAsAGroupOfTheirOwn() {
    let all: [FeatureDescriptor] = [.home, .timer, .tasks, .secrets, .screenText, .cleaning]
    var settings = ShellSettings()
    settings.settleAddedFeatures(all: all, isFreshInstall: true)
    let state = ShellFeature.State(settings: settings, features: all)
    #expect(state.onboarding.choosableFeatures.map(\.id) == ["timer", "tasks", "secrets"])
    #expect(state.onboarding.choosableUtilities.map(\.id) == ["screentext", "keyboard"])
    #expect(state.onboarding.chosen == ["timer", "tasks", "keyboard"])
  }
}
