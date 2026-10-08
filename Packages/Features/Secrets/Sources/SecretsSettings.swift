import ComposableArchitecture
import Foundation
import VortexCore

/// What the user sets for keys. Stored as JSON; unreadable keys fall back to their defaults.
public struct SecretsSettings: Codable, Equatable, Sendable {
  public static let defaultPort = 47823
  static let ports = 1024...65535

  /// Where the MCP server listens, on 127.0.0.1.
  public var port = Self.defaultPort
  /// Claude Code connected at least once, so the tab stops showing how to connect it.
  public var hasConnected = false

  private enum CodingKeys: String, CodingKey {
    case port, hasConnected
  }

  public init() {}

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let port = (try? container.decodeIfPresent(Int.self, forKey: .port)) ?? Self.defaultPort
    self.port = Self.ports.contains(port) ? port : Self.defaultPort
    hasConnected = (try? container.decodeIfPresent(Bool.self, forKey: .hasConnected)) ?? false
  }
}

extension SharedKey where Self == FileStorageKey<SecretsSettings>.Default {
  /// DataFolder/secrets.json.
  static var secretsSettings: Self {
    Self[.fileStorage(DataFolder.url.appending(path: "secrets.json")), default: SecretsSettings()]
  }
}
