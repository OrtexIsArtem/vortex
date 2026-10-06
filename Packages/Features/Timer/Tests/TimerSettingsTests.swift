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
    let settings = try decoded(#"{"sound": 5, "flashColor": "orange"}"#)
    #expect(settings.sound == TimerSettings.defaultSound)
    #expect(settings.flashColor == TimerSettings.defaultFlashColor)
  }

  @Test
  func anOlderFileKeepsItsSoundAndLeavesThePresetsBehind() throws {
    let settings = try decoded(#"{"presets": [5, 10, 45], "lastMinutes": 45, "sound": "Basso"}"#)
    #expect(settings.sound == "Basso")
    let saved = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any]
    #expect(saved?["presets"] == nil)
    #expect(saved?["lastMinutes"] == nil)
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
}
