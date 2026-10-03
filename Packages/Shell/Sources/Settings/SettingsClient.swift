import ComposableArchitecture
import Foundation

/// Reads and writes ~/Library/Application Support/Vortex/settings.json.
@DependencyClient
struct SettingsClient: Sendable {
  var load: @Sendable () -> ShellSettings = { ShellSettings() }
  var save: @Sendable (_ settings: ShellSettings) throws -> Void
}

extension SettingsClient: DependencyKey {
  static let liveValue: SettingsClient = {
    let url = URL.applicationSupportDirectory.appending(path: "Vortex/settings.json")
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
