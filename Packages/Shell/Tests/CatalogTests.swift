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
}
