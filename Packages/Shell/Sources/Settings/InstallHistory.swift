import ComposableArchitecture
import Foundation
import VortexCore

/// Whether Vortex runs for the first time on this Mac.
@DependencyClient
struct InstallHistory: Sendable {
  /// True while the data folder holds none of what Vortex keeps: no settings, no onboarding progress, no database.
  /// A settings file alone isn't enough to tell, as it is written only after a change or a clean quit.
  var isFresh: @Sendable () -> Bool = { false }

  static func isFresh(in folder: URL) -> Bool {
    let kept = ["settings.json", "onboarding.json", "vortex.sqlite"]
    return !kept.contains { FileManager.default.fileExists(atPath: folder.appending(path: $0).path) }
  }
}

extension InstallHistory: DependencyKey {
  static let liveValue = InstallHistory(isFresh: { isFresh(in: DataFolder.url) })
  static let testValue = InstallHistory()
}

extension DependencyValues {
  var installHistory: InstallHistory {
    get { self[InstallHistory.self] }
    set { self[InstallHistory.self] = newValue }
  }
}
