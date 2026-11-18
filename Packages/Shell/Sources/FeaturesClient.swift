import ComposableArchitecture
import FeatureRegistry
import Foundation
import VortexCore
import VortexPlatform

/// Lets ShellFeature reach the feature modules without knowing their types.
@DependencyClient
struct FeaturesClient: Sendable {
  /// Starts or stops the background work of a feature, see `FeatureModule.setEnabled`.
  var setEnabled: @Sendable (_ id: FeatureID, _ isEnabled: Bool) async -> Void
  /// Hands files to a feature that takes them, see `FeatureModule.receiveFiles`.
  var receiveFiles: @Sendable (_ id: FeatureID, _ urls: [URL]) async -> Void
  /// What the feature keeps on disk, in bytes: its folder (`FeatureModule.dataFolder`) and its settings file
  /// `<id>.json`; nil when it keeps neither.
  var dataSize: @Sendable (_ id: FeatureID) async -> Int64? = { _ in nil }
}

extension FeaturesClient: DependencyKey {
  /// Each call into a feature is marked in the launch record, so a crash inside it stops that feature next launch.
  static let liveValue = FeaturesClient(
    setEnabled: { id, isEnabled in
      @Dependency(\.launchGuard) var launchGuard
      await MainActor.run {
        launchGuard.around(id) { FeatureRegistry.module(for: id)?.setEnabled(isEnabled) }
      }
    },
    receiveFiles: { id, urls in
      @Dependency(\.launchGuard) var launchGuard
      await MainActor.run {
        launchGuard.around(id) { FeatureRegistry.module(for: id)?.receiveFiles(urls) }
      }
    },
    dataSize: { id in
      @Dependency(\.fileClient) var files
      // Plain data: no feature's code runs to tell its folder.
      let folder = await MainActor.run { FeatureRegistry.module(for: id)?.dataFolder }
      var bytes: Int64 = 0
      var keepsAnything = false
      if let folder {
        let url = DataFolder.url.appending(path: folder, directoryHint: .isDirectory)
        if await files.info(url) != nil {
          keepsAnything = true
          bytes += await files.folderSize(url)
        }
      }
      if let settings = await files.info(DataFolder.url.appending(path: "\(id).json")) {
        keepsAnything = true
        bytes += settings.size ?? 0
      }
      return keepsAnything ? bytes : nil
    }
  )

  static let testValue = FeaturesClient()
}

extension DependencyValues {
  var featuresClient: FeaturesClient {
    get { self[FeaturesClient.self] }
    set { self[FeaturesClient.self] = newValue }
  }
}
