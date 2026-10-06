import ComposableArchitecture
import Foundation
import VortexCore

/// What the user sets for the timer. Stored as JSON; unreadable keys fall back to their defaults.
public struct TimerSettings: Codable, Equatable, Sendable {
  /// Minutes. Home shows them next to the notch, half on each side, so no more than six fit.
  public static let defaultPresets = [5, 10, 15, 25, 45, 60]
  static let maxPresets = 6
  static let presetRange = 1...600
  public static let defaultSound = "Glass"
  /// A warm orange, apart from the blue and green of new files on the shelf.
  public static let defaultFlashColor = ColorValue(hex: 0xFF9F43)

  /// Minutes, ascending.
  public var presets = Self.defaultPresets
  /// The preset started last: marked on Home, and the Timer tab opens on it.
  public var lastMinutes = 25
  /// A system sound played when time is up; nil plays none.
  public var sound: String? = Self.defaultSound
  /// The color the notch flashes in when time is up.
  public var flashColor = Self.defaultFlashColor

  private enum CodingKeys: String, CodingKey {
    case presets, lastMinutes, sound, flashColor
  }

  public init() {}

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    presets = (try? container.decodeIfPresent([Int].self, forKey: .presets)).map(Self.normalized) ?? Self.defaultPresets
    // Minutes outside the range of the presets were never started by the user; kept, they would overflow the sums.
    lastMinutes = (try? container.decodeIfPresent(Int.self, forKey: .lastMinutes))
      .flatMap { Self.presetRange.contains($0) ? $0 : nil } ?? 25
    // A saved null is the user's "no sound"; a missing key, or a value that is not a name, is the default.
    if (try? container.decodeNil(forKey: .sound)) == true {
      sound = nil
    } else {
      sound = (try? container.decodeIfPresent(String.self, forKey: .sound)) ?? Self.defaultSound
    }
    flashColor = (try? container.decodeIfPresent(ColorValue.self, forKey: .flashColor)) ?? Self.defaultFlashColor
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(presets, forKey: .presets)
    try container.encode(lastMinutes, forKey: .lastMinutes)
    // Written even when nil, so "no sound" survives a relaunch.
    try container.encode(sound, forKey: .sound)
    try container.encode(flashColor, forKey: .flashColor)
  }

  /// "5, 10 25 abc 0" → [5, 10, 25]. Without a valid number left, the defaults.
  static func presets(from text: String) -> [Int] {
    normalized(text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap { Int($0) })
  }

  /// Within `presetRange`, ascending, without duplicates, the first `maxPresets`; the defaults when none is left.
  static func normalized(_ minutes: [Int]) -> [Int] {
    let valid = Set(minutes.filter { presetRange.contains($0) }).sorted().prefix(maxPresets)
    return valid.isEmpty ? defaultPresets : Array(valid)
  }

  /// The presets as the settings field shows them: "5, 10, 15".
  var presetsText: String {
    presets.map(String.init).joined(separator: ", ")
  }

  /// The preset the Timer tab opens on: the one started last, or the closest one when it is gone.
  var initialPreset: Int {
    presets.min { abs($0 - lastMinutes) < abs($1 - lastMinutes) } ?? lastMinutes
  }
}

extension SharedKey where Self == FileStorageKey<TimerSettings>.Default {
  /// DataFolder/timer.json.
  static var timerSettings: Self {
    Self[.fileStorage(DataFolder.url.appending(path: "timer.json")), default: TimerSettings()]
  }
}
