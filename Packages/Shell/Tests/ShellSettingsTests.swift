import Foundation
import Testing
import VortexCore

@testable import VortexShell

struct ShellSettingsTests {
  func decode(_ json: String) throws -> ShellSettings {
    try JSONDecoder().decode(ShellSettings.self, from: Data(json.utf8))
  }

  @Test
  func emptyFileGivesDefaults() throws {
    #expect(try decode("{}") == ShellSettings())
  }

  @Test
  func brokenOldAndUnknownValuesFallBackToDefaults() throws {
    let settings = try decode(#"{"hoverDelay": "fast", "theme": "sepia", "openOnClick": false, "language": "uk", "fromTheFuture": 1}"#)
    #expect(settings.hoverDelay == 0.3)
    #expect(settings.theme == .system)
    #expect(settings.openOnClick == false)
  }

  @Test
  func delaysStayWithinZeroToTwoSeconds() throws {
    let settings = try decode(#"{"hoverDelay": 9, "pointerLeaveDelay": -1}"#)
    #expect(settings.hoverDelay == 2)
    #expect(settings.pointerLeaveDelay == 0)
  }

  @Test
  func roundTrip() throws {
    var settings = ShellSettings()
    settings.featureOrder = ["tasks", "timer"]
    settings.disabledFeatures = ["timer"]
    settings.lastTab = "feature:tasks"
    settings.theme = .dark
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(ShellSettings.self, from: data) == settings)
  }

  /// A launch that settles the added features writes them at once: otherwise a fresh install that quit uncleanly
  /// before its first save (onboarding.json is written at once) would come back as an update, with every feature added
  /// and running. A launch with nothing new to write writes nothing; one that stops a feature does.
  @Test
  func aLaunchThatSettlesOrStopsFeaturesSavesAtOnce() {
    var settings = ShellSettings()
    let all: [FeatureDescriptor] = [.home, .timer, .secrets]
    let firstSettling = settings.prepareLaunch(all: all, isFreshInstall: true, verdict: .normal, version: "1")
    #expect(firstSettling)
    #expect(settings.addedFeatures == ["home", "timer"] && !settings.featuresChosen)
    let nothingNew = settings.prepareLaunch(all: all, isFreshInstall: false, verdict: .normal, version: "1")
    #expect(!nothingNew)
    let stop = settings.prepareLaunch(all: all, isFreshInstall: false, verdict: .stop("timer"), version: "1")
    #expect(stop)
    #expect(settings.stoppedFeatures == ["timer"])
  }

  @Test
  func anUpdateKeepsTheFeaturesTheUserHad() {
    var settings = ShellSettings()
    settings.disabledFeatures = ["tasks"]
    settings.settleAddedFeatures(all: [.home, .timer, .tasks, .secrets], isFreshInstall: false)
    #expect(settings.addedFeatures == ["home", "timer", "secrets"])
    #expect(settings.disabledFeatures.isEmpty && settings.featuresChosen)
    #expect(Set(settings.seenFeatures) == ["home", "timer", "tasks", "secrets"])
  }

  @Test
  func aFreshInstallStartsWithTheRecommendedOnesNotYetChosen() {
    var settings = ShellSettings()
    settings.settleAddedFeatures(all: [.home, .timer, .tasks, .secrets], isFreshInstall: true)
    #expect(settings.addedFeatures == ["home", "timer", "tasks"])
    #expect(!settings.featuresChosen)
    #expect(Set(settings.seenFeatures) == ["home", "timer", "tasks", "secrets"])
  }

  @Test
  func settledFeaturesAreNeverResettled() {
    var settings = ShellSettings()
    settings.settleAddedFeatures(all: [.home, .timer], isFreshInstall: false)
    settings.settleAddedFeatures(all: [.home, .timer, .tasks, .secrets], isFreshInstall: true)
    #expect(settings.addedFeatures == ["home", "timer"])
    #expect(settings.featuresChosen)
  }

  @Test
  func oldSettingsFilesDecodeWithoutTheNewKeys() throws {
    let settings = try decode(#"{"disabledFeatures": ["tasks"], "featureOrder": ["timer"]}"#)
    #expect(settings.addedFeatures == nil)
    #expect(settings.disabledFeatures == ["tasks"])
    #expect(settings.featuresChosen)
    #expect(settings.seenFeatures.isEmpty && settings.stoppedFeatures.isEmpty && settings.pendingErase.isEmpty)
  }

  @Test
  @MainActor
  func theShellSettlesOldSettingsLikeAnUpdate() {
    var settings = ShellSettings()
    settings.disabledFeatures = ["tasks"]
    let state = ShellFeature.State(settings: settings, features: [.timer, .shelf, .tasks])
    #expect(state.settings.addedFeatures == ["timer", "shelf"])
    #expect(state.sidebarFeatures.map(\.id) == ["timer", "shelf"])
  }

  @Test
  func anInstallIsFreshOnlyWithoutSettingsOnboardingAndDatabase() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "vortex-install-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(InstallHistory.isFresh(in: folder))
    for name in ["onboarding.json", "settings.json", "vortex.sqlite"] {
      let file = folder.appending(path: name)
      try Data().write(to: file)
      #expect(!InstallHistory.isFresh(in: folder), "\(name)")
      try FileManager.default.removeItem(at: file)
    }
  }

  @Test
  func tabsSurviveStorage() {
    for tab in [ShellFeature.Tab.settings, .feature("timer")] {
      #expect(ShellFeature.Tab(storageValue: tab.storageValue) == tab)
    }
  }
}
