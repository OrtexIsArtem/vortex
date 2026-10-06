import Foundation
import Testing
import VortexCore

@testable import FeatureTimer

struct TimerSettingsTests {
  func decoded(_ json: String) throws -> TimerSettings {
    try JSONDecoder().decode(TimerSettings.self, from: Data(json.utf8))
  }

  @Test
  func missingOrBrokenKeysFallBackToDefaults() throws {
    let settings = try decoded(#"{"lastMinutes": "x", "sound": 5}"#)
    #expect(settings.minutes == TimerSettings.defaultMinutes)
    #expect(settings.sound == TimerSettings.defaultSound)
    #expect(settings.flashColor == TimerSettings.defaultFlashColor)
  }

  @Test
  func theMinutesOfTheLastPresetCarryOverAndTheOldPresetsAreLeftBehind() throws {
    let settings = try decoded(#"{"presets": [5, 10, 45], "lastMinutes": 45, "sound": "Basso"}"#)
    #expect(settings.minutes == 45)
    #expect(settings.sound == "Basso")
    let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
    #expect(saved?["lastMinutes"] as? Int == 45)
    #expect(saved?["presets"] == nil)
  }

  @Test
  func minutesPastEitherEndOfTheDrumMoveToThatEnd() throws {
    for (saved, minutes) in [("-5", 1), ("0", 1), ("121", 120), ("600", 120), ("-9223372036854775808", 1), ("9223372036854775807", 120)] {
      #expect(try decoded(#"{"lastMinutes": \#(saved)}"#).minutes == minutes)
    }
    #expect(try decoded(#"{"lastMinutes": 1}"#).minutes == 1)
    #expect(try decoded(#"{"lastMinutes": 120}"#).minutes == 120)
    // Not a whole number of minutes at all.
    #expect(try decoded(#"{"lastMinutes": 7.5}"#).minutes == TimerSettings.defaultMinutes)
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
    settings.minutes = 7
    let decoded = try JSONDecoder().decode(TimerSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded == settings)
  }
}
