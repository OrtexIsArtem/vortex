import ComposableArchitecture
import Foundation
import VortexCore
import VortexPlatform

/// What the user sets for the clipboard. Stored as JSON; unreadable keys fall back to their defaults.
public struct ClipboardSettings: Codable, Equatable, Sendable {
  /// Nothing copied in these apps is kept.
  public var ignoredApps: [AppInfo] = []

  public init() {}

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    ignoredApps = (try? container.decodeIfPresent([AppInfo].self, forKey: .ignoredApps)) ?? []
  }
}

extension SharedKey where Self == FileStorageKey<ClipboardSettings>.Default {
  /// DataFolder/clipboard.json.
  static var clipboardSettings: Self {
    Self[.fileStorage(DataFolder.url.appending(path: "clipboard.json")), default: ClipboardSettings()]
  }
}
