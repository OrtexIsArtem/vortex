import ComposableArchitecture
import Foundation
import VortexCore

/// Reads and writes DataFolder/settings.json.
@DependencyClient
struct SettingsClient: Sendable {
  var load: @Sendable () -> ShellSettings = { ShellSettings() }
  var save: @Sendable (_ settings: ShellSettings) throws -> Void
}

extension SettingsClient: DependencyKey {
  static let liveValue: SettingsClient = {
    let url = DataFolder.url.appending(path: "settings.json")
    return SettingsClient(
      load: {
        guard let data = try? Data(contentsOf: url) else { return ShellSettings() }
        return (try? JSONDecoder().decode(ShellSettings.self, from: data)) ?? ShellSettings()
      },
      save: { settings in
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
      }
    )
  }()

  static let testValue = SettingsClient()
}

extension DependencyValues {
  var settingsClient: SettingsClient {
    get { self[SettingsClient.self] }
    set { self[SettingsClient.self] = newValue }
  }
}
