import ComposableArchitecture
import Foundation
import VortexCore

/// What the user sets for keys. Stored as JSON; unreadable keys fall back to their defaults.
public struct SecretsSettings: Codable, Equatable, Sendable {
  public static let defaultPort = 47823
  static let ports = 1024...65535
  /// In DataFolder. A QA run writes its own port under `port` in this file before Keys starts (VortexPlatform's
  /// `QAIsolation.seedServerPort`): renaming the file or the key would send QA runs back to 47823.
  static let fileName = "secrets.json"

  /// Where the MCP server listens, on 127.0.0.1.
  public var port = Self.defaultPort
  /// Claude Code connected at least once, so the tab stops showing how to connect it.
  public var hasConnected = false
  /// The onboarding's "Connect" added Vortex to Claude Code: the step stays done after a relaunch.
  public var addedToClaudeCode = false

  private enum CodingKeys: String, CodingKey {
    case port, hasConnected, addedToClaudeCode
  }

  public init() {}

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let port = (try? container.decodeIfPresent(Int.self, forKey: .port)) ?? Self.defaultPort
    self.port = Self.ports.contains(port) ? port : Self.defaultPort
    hasConnected = (try? container.decodeIfPresent(Bool.self, forKey: .hasConnected)) ?? false
    addedToClaudeCode = (try? container.decodeIfPresent(Bool.self, forKey: .addedToClaudeCode)) ?? false
  }
}

extension SharedKey where Self == FileStorageKey<SecretsSettings>.Default {
  /// DataFolder/secrets.json.
  static var secretsSettings: Self {
    Self[.fileStorage(DataFolder.url.appending(path: SecretsSettings.fileName)), default: SecretsSettings()]
  }
}
