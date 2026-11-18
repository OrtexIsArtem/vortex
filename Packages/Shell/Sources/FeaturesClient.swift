import ComposableArchitecture
import FeatureRegistry
import Foundation
import VortexCore

/// Lets ShellFeature reach the feature modules without knowing their types.
@DependencyClient
struct FeaturesClient: Sendable {
  /// Starts or stops the background work of a feature, see `FeatureModule.setEnabled`.
  var setEnabled: @Sendable (_ id: FeatureID, _ isEnabled: Bool) async -> Void
  /// Hands files to a feature that takes them, see `FeatureModule.receiveFiles`.
  var receiveFiles: @Sendable (_ id: FeatureID, _ urls: [URL]) async -> Void
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
