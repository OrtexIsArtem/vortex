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

  func decoded(_ json: String) throws -> TimerSettings {
    try JSONDecoder().decode(TimerSettings.self, from: Data(json.utf8))
  }

  @Test
  func lastMinutesOutsideThePresetRangeFallBackToTwentyFive() throws {
    for minutes in ["-5", "0", "601", "9999", "-9223372036854775808", "9223372036854775807"] {
      let settings = try decoded(#"{"lastMinutes": \#(minutes)}"#)
      #expect(settings.lastMinutes == 25)
      // The sum that once overflowed on the smallest of these.
      #expect(settings.initialPreset == 25)
    }
    #expect(try decoded(#"{"lastMinutes": 1}"#).lastMinutes == 1)
    #expect(try decoded(#"{"lastMinutes": 600}"#).lastMinutes == 600)
    // Not a whole number of minutes at all.
    #expect(try decoded(#"{"lastMinutes": 7.5}"#).lastMinutes == 25)
    #expect(try decoded(#"{"lastMinutes": "ten"}"#).lastMinutes == 25)
  }

  @Test
  func onlyASavedNullMeansNoSound() throws {
    #expect(try decoded(#"{"sound": null}"#).sound == nil)
    // A value that is no name, or a missing key, is the default, not "no sound".
    #expect(try decoded(#"{"sound": 5}"#).sound == TimerSettings.defaultSound)
    #expect(try decoded(#"{"sound": ["Basso"]}"#).sound == TimerSettings.defaultSound)
    #expect(try decoded(#"{}"#).sound == TimerSettings.defaultSound)
    #expect(try decoded(#"{"sound": "Basso"}"#).sound == "Basso")
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
