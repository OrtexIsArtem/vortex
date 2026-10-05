import ComposableArchitecture
import Foundation
import VortexCore

/// What the user sets for the shelf. Stored as JSON; unreadable keys fall back to their defaults.
public struct ShelfSettings: Codable, Equatable, Sendable {
  /// Types a folder takes when it is added without an example file.
  public static let defaultExtensions = ["ipa", "apk", "aab", "dmg", "zip"]

  /// Folders whose new files land on the shelf, such as the folder a build script writes to.
  public var watchedFolders: [WatchedFolder] = []

  /// A folder and the file types it passes on to the shelf. Build files get a new name every time
  /// (`app-1.0.0-65-20260923-230220.aab`), so the folder and the type are what stays the same.
  public struct WatchedFolder: Codable, Equatable, Identifiable, Sendable {
    public var folder: URL
    /// Lowercased, without dots; empty takes every file.
    public var extensions: [String]

    public var id: URL { folder }

    /// The folder is kept in one spelling, without a trailing slash, so the same folder is never added twice.
    public init(folder: URL, extensions: [String]) {
      self.folder = URL(filePath: folder.standardizedFileURL.path, directoryHint: .notDirectory)
      self.extensions = extensions
    }

    /// Whether a new file belongs on the shelf: it is in the folder or below, and of one of its types.
    func takes(_ url: URL) -> Bool {
      guard url.path.hasPrefix(folder.path + "/"), !url.lastPathComponent.hasPrefix(".") else { return false }
      return extensions.isEmpty || extensions.contains(url.pathExtension.lowercased())
    }
  }

  public init() {}

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    watchedFolders = (try? container.decodeIfPresent([WatchedFolder].self, forKey: .watchedFolders)) ?? []
  }

  /// Whether a new file found in one of the watched folders belongs on the shelf.
  func takes(_ url: URL) -> Bool {
    watchedFolders.contains { $0.takes(url) }
  }

  /// "ipa, .APK  dmg" → ["ipa", "apk", "dmg"].
  static func extensions(from text: String) -> [String] {
    var seen = Set<String>()
    return text
      .split(whereSeparator: { $0 == "," || $0.isWhitespace })
      .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".*")).lowercased() }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  /// What a path the user gives means: a folder to watch for the usual build types; an example file, whose folder is
  /// watched for files of its type; or a pattern like `…/last_builds/*.aab`. Leading `~` is the home folder.
  static func watchedFolder(forPath text: String, isDirectory: Bool) -> WatchedFolder {
    let url = URL(fileURLWithPath: NSString(string: text.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath)
      .standardizedFileURL
    if isDirectory {
      return WatchedFolder(folder: url, extensions: defaultExtensions)
    }
    let type = url.pathExtension.lowercased()
    return WatchedFolder(folder: url.deletingLastPathComponent(), extensions: type.isEmpty ? defaultExtensions : [type])
  }
}

extension SharedKey where Self == FileStorageKey<ShelfSettings>.Default {
  /// DataFolder/shelf.json.
  static var shelfSettings: Self {
    Self[.fileStorage(DataFolder.url.appending(path: "shelf.json")), default: ShelfSettings()]
  }
}
