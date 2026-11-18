import ComposableArchitecture
import Foundation
import Testing
import VortexCore

@testable import VortexShell

extension FeatureDescriptor {
  static let music = FeatureDescriptor(id: "music", title: "Music", symbol: "music.note")
}

@MainActor
struct CatalogTests {
  let shell = ShellFeatureTests()

  /// Entering the catalog counts every feature as seen, but the ones that were new keep their badge for this visit.
  @Test
  func openingTheCatalogMarksEverythingSeenButKeepsTheBadgesForTheVisit() async {
    let store = shell.makeStore(features: [.timer, .music]) {
      $0.addedFeatures = ["timer"]
      $0.seenFeatures = ["timer"]
    }
    #expect(store.state.catalogDot)
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalog)) {
      $0.selectedTab = .catalog
      $0.openReason = .click
      $0.visitNew = ["music"]
      $0.settings.seenFeatures = ["timer", "music"]
    }
    #expect(!store.state.catalogDot)
    await shell.clock.advance(by: .milliseconds(400))
  }

  /// Leaving the catalog, by a tab or by closing the window, drops the badges: the next visit has nothing new.
  @Test
  func leavingTheCatalogDropsTheNewBadges() async {
    let store = shell.makeStore(features: [.timer, .music]) {
      $0.addedFeatures = ["timer"]
      $0.seenFeatures = ["timer"]
    }
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalog)) {
      $0.selectedTab = .catalog
      $0.openReason = .click
      $0.visitNew = ["music"]
      $0.settings.seenFeatures = ["timer", "music"]
    }
    await store.send(.tabSelected(.feature("timer"))) {
      $0.selectedTab = .feature("timer")
      $0.settings.lastTab = "feature:timer"
      $0.visitNew = []
    }
    await store.send(.tabSelected(.catalog)) { $0.selectedTab = .catalog }
    await store.send(.window(.escapePressed)) {
      $0.openReason = nil
      $0.selectedTab = .feature("timer")
    }
    await shell.clock.advance(by: .milliseconds(400))
  }

  /// A feature stopped after a crash lights the catalog's dot until it runs again.
  @Test
  func aStoppedFeatureLightsTheDot() {
    var settings = ShellSettings()
    settings.addedFeatures = ["timer", "tasks"]
    settings.seenFeatures = ["timer", "tasks"]
    #expect(!ShellFeature.State(settings: settings, features: [.timer, .tasks]).catalogDot)
    settings.stoppedFeatures = ["tasks"]
    #expect(ShellFeature.State(settings: settings, features: [.timer, .tasks]).catalogDot)
  }

  /// In safe mode the features that wait light the dot; once all of them run it goes out.
  @Test
  func safeModeLightsTheDotWhileFeaturesWait() {
    var settings = ShellSettings()
    settings.addedFeatures = ["home", "timer"]
    settings.seenFeatures = ["home", "timer"]
    var state = ShellFeature.State(settings: settings, features: [.home, .timer], isSafeMode: true)
    #expect(state.catalogDot)
    state.safeModeStarted = ["timer"]
    #expect(!state.catalogDot)
  }

  /// A feature paused in this release is never new, so it lights nothing and gets no badge.
  @Test
  func pausedFeaturesAreNeverNew() async {
    let paused = FeatureDescriptor(id: "music", title: "Music", symbol: "music.note", suspension: "Broken on this macOS.")
    let store = shell.makeStore(features: [.timer, paused]) {
      $0.addedFeatures = ["timer"]
      $0.seenFeatures = ["timer"]
    }
    #expect(!store.state.catalogDot)
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalog)) {
      $0.selectedTab = .catalog
      $0.openReason = .click
      $0.settings.seenFeatures = ["timer", "music"]
    }
    await shell.clock.advance(by: .milliseconds(400))
  }

  /// The catalog leaves out built-in features; among those you can add the recommended ones come first.
  @Test
  func recommendedOnesComeFirstAmongThoseYouCanAdd() {
    var settings = ShellSettings()
    settings.addedFeatures = ["home", "timer"]
    let state = ShellFeature.State(settings: settings, features: [.home, .timer, .secrets, .music, .tasks])
    #expect(state.catalogFeatures.map(\.id) == ["timer", "secrets", "music", "tasks"])
    #expect(state.catalogAdded.map(\.id) == ["timer"])
    #expect(state.catalogAvailable.map(\.id) == ["tasks", "secrets", "music"])
  }

  // MARK: - A feature's page

  /// Add starts the feature on a trial, saved before it runs; its tab is the one the window opens on next, while the
  /// window stays on the page.
  @Test
  func addingStartsTheFeatureAsATrialAndRemembersItsTab() async {
    let store = shell.makeStore {
      $0.addedFeatures = ["timer", "shelf"]
      $0.seenFeatures = ["timer", "shelf", "tasks"]
    }
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalogPage("tasks"))) {
      $0.selectedTab = .catalogPage("tasks")
      $0.openReason = .click
    }
    await store.send(.featureAdded("tasks")) {
      $0.settings.addedFeatures = ["timer", "shelf", "tasks"]
      $0.settings.lastTab = "feature:tasks"
    }
    #expect(shell.saved.value.last?.addedFeatures == ["timer", "shelf", "tasks"])
    #expect(shell.trials.value == ["tasks"])
    await shell.clock.advance(by: .milliseconds(400))
    await store.finish()
    #expect(shell.featureSwitches.value == ["tasks:true"])
    #expect(store.state.pageState("tasks") == .added(needsSetup: false))
  }

  /// Remove stops the feature, leaves its tab and offers Undo for 5 s, which adds it back.
  @Test
  func removingStopsItLeavesItsTabAndOffersUndo() async {
    let store = shell.makeStore { $0.seenFeatures = ["timer", "shelf", "tasks"] }
    await shell.openByHover(store)
    #expect(store.state.selectedTab == .feature("timer"))
    await store.send(.featureRemoved("timer")) {
      $0.settings.addedFeatures = ["shelf", "tasks"]
      $0.selectedTab = .feature("shelf")
      $0.removedForUndo = "timer"
    }
    #expect(shell.saved.value.last?.addedFeatures == ["shelf", "tasks"])
    await store.send(.undoRemoveTapped) {
      $0.settings.addedFeatures = ["timer", "shelf", "tasks"]
      $0.settings.lastTab = "feature:timer"
      $0.removedForUndo = nil
    }
    await store.send(.featureRemoved("tasks")) {
      $0.settings.addedFeatures = ["timer", "shelf"]
      $0.removedForUndo = "tasks"
    }
    await shell.clock.advance(by: .seconds(5))
    await store.receive(\.undoExpired) { $0.removedForUndo = nil }
    await store.finish()
    #expect(shell.featureSwitches.value == ["timer:false", "timer:true", "tasks:false"])
    #expect(shell.trials.value == ["timer"])
  }

  /// Esc on a feature's page goes back to the list; on the list it closes the window.
  @Test
  func escapeOnAFeaturePageGoesBackToTheList() async {
    let store = shell.makeStore { $0.seenFeatures = ["timer", "shelf", "tasks"] }
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalogPage("tasks"))) {
      $0.selectedTab = .catalogPage("tasks")
      $0.openReason = .click
    }
    await store.send(.window(.escapePressed)) { $0.selectedTab = .catalog }
    await store.send(.window(.escapePressed)) {
      $0.openReason = nil
      $0.selectedTab = .feature("timer")
    }
    #expect(shell.dismissals.value == 1)
  }

  /// A feature whose own setup step isn't done shows it on its page.
  @Test
  func aFeatureWithAnUnfinishedStepShowsItOnThePage() {
    let keys = FeatureDescriptor(id: "secrets", title: "Keys", symbol: "key.horizontal", hasOnboardingStep: true)
    var settings = ShellSettings()
    settings.addedFeatures = ["timer", "secrets"]
    let state = ShellFeature.State(settings: settings, features: [.timer, keys, .shelf])
    #expect(state.pageState("secrets") == .added(needsSetup: true))
    #expect(state.pageState("timer") == .added(needsSetup: false))
    #expect(state.pageState("shelf") == .available)
    @Shared(.onboardingStepsDone) var stepsDone
    $stepsDone.withLock { $0 = ["secrets"] }
    #expect(state.pageState("secrets") == .added(needsSetup: false))
  }

  /// Files given to Vortex while no running feature takes them open the page of the one that would, and wait for it.
  @Test
  func filesNobodyTakesOpenTheShelfPage() async {
    let store = shell.makeStore {
      $0.addedFeatures = ["timer", "tasks"]
      $0.seenFeatures = ["timer", "shelf", "tasks"]
    }
    let file = URL(fileURLWithPath: "/tmp/a.ipa")
    await store.send(.filesReceived([file])) {
      $0.openReason = .hotkey
      $0.selectedTab = .catalogPage("shelf")
      $0.pendingFiles = [file]
    }
    #expect(shell.windowLog.value == ["size:large", "present:hotkey"])
    await store.send(.featureAdded("shelf")) {
      $0.settings.addedFeatures = ["timer", "shelf", "tasks"]
      $0.settings.lastTab = "feature:shelf"
      $0.pendingFiles = []
    }
    await shell.clock.advance(by: .milliseconds(400))
    await store.finish()
    #expect(shell.featureSwitches.value == ["shelf:true"])
    #expect(shell.receivedFiles.value == ["shelf:a.ipa"])
  }
}
