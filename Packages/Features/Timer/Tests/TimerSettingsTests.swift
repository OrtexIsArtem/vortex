import Foundation
import Testing
import VortexCore

@testable import FeatureTimer

struct TimerSettingsTests {
  @Test
  func presetsAreCleanedUpFromText() {
    #expect(TimerSettings.presets(from: "25, 5 10,abc 0 5 700") == [5, 10, 25])
    #expect(TimerSettings.presets(from: "1 2 3 4 5 6 7") == [1, 2, 3, 4, 5, 6])
    #expect(TimerSettings.presets(from: "  ") == TimerSettings.defaultPresets)
  }

  @Test
  func missingOrBrokenKeysFallBackToDefaults() throws {
    let settings = try JSONDecoder().decode(TimerSettings.self, from: Data(#"{"presets": "x", "lastMinutes": 10}"#.utf8))
    #expect(settings.presets == TimerSettings.defaultPresets)
    #expect(settings.lastMinutes == 10)
    #expect(settings.sound == TimerSettings.defaultSound)
    #expect(settings.flashColor == TimerSettings.defaultFlashColor)
  }

  @Test
  func noSoundSurvivesSaving() throws {
    var settings = TimerSettings()
    settings.sound = nil
    let decoded = try JSONDecoder().decode(TimerSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded == settings)
  }

  @Test
  func theTabOpensOnTheLastPresetOrTheClosestOne() {
    var settings = TimerSettings()
    #expect(settings.initialPreset == 25)
    settings.presets = [5, 30, 60]
    #expect(settings.initialPreset == 30)
    #expect(settings.presetsText == "5, 30, 60")
  }
}
