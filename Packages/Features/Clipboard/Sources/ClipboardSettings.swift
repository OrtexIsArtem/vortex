import ComposableArchitecture
import Foundation
import VortexCore
import VortexPlatform

/// How long an unpinned item stays in the history after it was last copied.
public enum HistoryLifetime: String, Codable, CaseIterable, Sendable {
  case week
  case month
  case threeMonths
  case year
  case forever

  /// nil: never removed by age.
  var days: Int? {
    switch self {
    case .week: 7
    case .month: 30
    case .threeMonths: 90
    case .year: 365
    case .forever: nil
    }
  }
}

/// What the user sets for the clipboard. Stored as JSON; unreadable keys fall back to their defaults.
public struct ClipboardSettings: Codable, Equatable, Sendable {
  /// Nothing copied in these apps is kept.
  public var ignoredApps: [AppInfo] = []
  public var historyLifetime = HistoryLifetime.month

  public init() {}

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    ignoredApps = (try? container.decodeIfPresent([AppInfo].self, forKey: .ignoredApps)) ?? []
    historyLifetime = (try? container.decodeIfPresent(HistoryLifetime.self, forKey: .historyLifetime)) ?? .month
  }
}

extension SharedKey where Self == FileStorageKey<ClipboardSettings>.Default {
  /// DataFolder/clipboard.json.
  static var clipboardSettings: Self {
    Self[.fileStorage(DataFolder.url.appending(path: "clipboard.json")), default: ClipboardSettings()]
  }
}
