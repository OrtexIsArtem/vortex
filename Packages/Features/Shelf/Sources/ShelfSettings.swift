import ComposableArchitecture
import Foundation
import VortexCore

/// What the user sets for the shelf. Stored as JSON; unreadable keys fall back to their defaults.
public struct ShelfSettings: Codable, Equatable, Sendable {
  public static let defaultExtensions = ["ipa", "apk", "dmg", "zip"]

  /// New files appearing in this folder or its subfolders land on the shelf; nil watches nothing.
  public var watchedFolder: URL?
  /// Extensions of files the folder passes on, lowercased, without dots; empty passes every file.
  public var watchedExtensions = Self.defaultExtensions

  public init() {}

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    watchedFolder = try? container.decodeIfPresent(URL.self, forKey: .watchedFolder)
    watchedExtensions = (try? container.decodeIfPresent([String].self, forKey: .watchedExtensions)) ?? Self.defaultExtensions
  }

  /// Whether a file found in the watched folder belongs on the shelf.
  func passes(_ url: URL) -> Bool {
    guard !url.lastPathComponent.hasPrefix(".") else { return false }
    return watchedExtensions.isEmpty || watchedExtensions.contains(url.pathExtension.lowercased())
  }

  /// "ipa, .APK  dmg" → ["ipa", "apk", "dmg"].
  static func extensions(from text: String) -> [String] {
    var seen = Set<String>()
    return text
      .split(whereSeparator: { $0 == "," || $0.isWhitespace })
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
  }
}

extension SharedKey where Self == FileStorageKey<ShelfSettings>.Default {
  /// DataFolder/shelf.json.
  static var shelfSettings: Self {
    Self[.fileStorage(DataFolder.url.appending(path: "shelf.json")), default: ShelfSettings()]
  }
}
