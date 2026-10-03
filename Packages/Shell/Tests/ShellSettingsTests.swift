import Foundation
import Testing

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
  func brokenAndUnknownValuesFallBackToDefaults() throws {
    let settings = try decode(#"{"hoverDelay": "fast", "theme": "sepia", "openOnClick": false, "fromTheFuture": 1}"#)
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
    settings.language = .ukrainian
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(ShellSettings.self, from: data) == settings)
  }

  @Test
  func tabsSurviveStorage() {
    for tab in [ShellFeature.Tab.settings, .feature("timer")] {
      #expect(ShellFeature.Tab(storageValue: tab.storageValue) == tab)
    }
  }
}
