import ComposableArchitecture
import Foundation
import Testing
import VortexCore

@testable import VortexShell

extension FeatureDescriptor {
  /// A utility, as Screen Text: its utility action, its settings, its shortcut and the notch are all it shows.
  static let screenText = FeatureDescriptor(id: "screentext", title: "Screen Text", symbol: "text.viewfinder", kind: .utility)
}

/// A feature without a tab runs like any other, but has no tab: no sidebar icon, no Open on its page, no shortcut that
/// opens its tab. Its page in Settings › Features holds its own settings.
@MainActor
struct TablessFeatureTests {
  let shell = ShellFeatureTests()

  var settings: ShellSettings {
    var settings = ShellSettings()
    settings.addedFeatures = ["home", "timer", "screentext"]
    settings.featureOrder = ["home", "screentext", "timer"]
    return settings
  }

  @Test
  func itRunsWithoutASidebarIconAndHasASettingsPage() {
    let state = ShellFeature.State(settings: settings, features: [.home, .timer, .screenText], onboarding: .finished)
    #expect(state.runningFeatures.map(\.id) == ["home", "screentext", "timer"])
    #expect(state.sidebarFeatures.map(\.id) == ["home", "timer"])
    #expect(!state.isAvailable(.feature("screentext")))
    // Its own settings are what it has to set: its page lists it in sidebar order.
    #expect(state.settingsFeatures.map(\.id) == ["home", "screentext", "timer"])
    #expect(state.hasSettingsPage("screentext"))
    #expect(state.tabShortcut("screentext") == nil)
    #expect(state.tabShortcut("timer") == .open("timer"))
  }

  /// Its page in the catalog has no Open, as there's nothing to open; Settings and Remove stay.
  @Test
  func itsCatalogPageHasNoOpen() {
    let state = ShellFeature.State(settings: settings, features: [.home, .timer, .screenText], onboarding: .finished)
    #expect(state.pageState("screentext") == .added(needsSetup: false))
    #expect(!state.pageOffersOpen("screentext"))
    #expect(state.pageOffersOpen("timer"))
    #expect(state.hasSettingsPage("screentext"))
  }

  /// No shortcut opens its tab: none is listened for at launch, nor once it is added again, and pressing one does
  /// nothing.
  @Test
  func noShortcutOpensItsTab() async {
    let asked = LockIsolated<[String]>([])
    let store = shell.makeStore(features: [.home, .timer, .screenText]) {
      $0.addedFeatures = ["home", "timer", "screentext"]
    }
    store.dependencies.hotkeyClient.presses = { hotkey in
      asked.withValue { $0.append(hotkey.name) }
      return AsyncStream { _ in }
    }
    let task = await shell.launch(store)
    await store.send(.featureHotkeyPressed("screentext"))
    #expect(shell.presented.value.isEmpty)

    await store.send(.featureRemoved("screentext")) {
      $0.settings.addedFeatures = ["home", "timer"]
      $0.removedForUndo = "screentext"
    }
    await store.send(.undoRemoveTapped) {
      $0.settings.addedFeatures = ["home", "timer", "screentext"]
      $0.removedForUndo = nil
    }
    await shell.clock.advance(by: .milliseconds(400))
    await task.cancel()
    await store.finish()
    #expect(Set(asked.value) == ["openVortex", "open-home", "open-timer"])
    #expect(shell.featureSwitches.value == ["home:true", "timer:true", "screentext:true", "screentext:false", "screentext:true"])
  }

  /// Adding it starts it, and the window still opens next on the tab it opened on: it has none of its own.
  @Test
  func addingItKeepsTheTabTheWindowOpensOn() async {
    let store = shell.makeStore(features: [.home, .timer, .screenText]) {
      $0.addedFeatures = ["home", "timer"]
      $0.seenFeatures = ["home", "timer", "screentext"]
      $0.lastTab = "feature:timer"
    }
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalogPage("screentext"))) {
      $0.selectedTab = .catalogPage("screentext")
      $0.openReason = .click
    }
    await store.send(.featureAdded("screentext")) {
      $0.settings.addedFeatures = ["home", "timer", "screentext"]
    }
    #expect(shell.trials.value == ["screentext"])
    #expect(store.state.restoredTab == .feature("timer"))
    // Its page's Settings goes to its own page in Settings › Features.
    await store.send(.featureSettingsTapped("screentext")) {
      $0.selectedTab = .settings
      $0.settings.lastTab = "settings"
      $0.settingsSection = .features
      $0.settingsFeature = "screentext"
    }
    await shell.clock.advance(by: .milliseconds(400))
    await store.finish()
    #expect(shell.featureSwitches.value == ["screentext:true"])
  }

  /// Its notch indicator's ear opens the last tab, as the cutout does: there is no tab of its own to open.
  @Test
  func itsEarOpensTheLastTab() async {
    let store = shell.makeStore(features: [.home, .timer, .screenText]) {
      $0.addedFeatures = ["home", "timer", "screentext"]
      $0.lastTab = "feature:timer"
    }
    await store.send(.window(.notchClicked(feature: "screentext"))) {
      $0.openReason = .click
      $0.selectedTab = .feature("timer")
    }
  }
}
