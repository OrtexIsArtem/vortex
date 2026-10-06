import ComposableArchitecture
import Foundation
import VortexCore

/// What the user sets for the timer. Stored as JSON; unreadable keys fall back to their defaults.
public struct TimerSettings: Codable, Equatable, Sendable {
  public static let defaultSound = "Glass"
  /// A warm orange, apart from the blue and green of new files on the shelf.
  public static let defaultFlashColor = ColorValue(hex: 0xFF9F43)

  /// A system sound played when time is up; nil plays none.
  public var sound: String? = Self.defaultSound
  /// The color the notch flashes in when time is up.
  public var flashColor = Self.defaultFlashColor

  private enum CodingKeys: String, CodingKey {
    case sound, flashColor
  }

  public init() {}

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
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
    // Written even when nil, so "no sound" survives a relaunch.
    try container.encode(sound, forKey: .sound)
    try container.encode(flashColor, forKey: .flashColor)
  }
}

extension SharedKey where Self == FileStorageKey<TimerSettings>.Default {
  /// DataFolder/timer.json.
  static var timerSettings: Self {
    Self[.fileStorage(DataFolder.url.appending(path: "timer.json")), default: TimerSettings()]
  }
}
