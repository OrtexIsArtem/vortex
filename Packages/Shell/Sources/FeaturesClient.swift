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
  static let liveValue = FeaturesClient(
    setEnabled: { id, isEnabled in
      await MainActor.run { FeatureRegistry.module(for: id)?.setEnabled(isEnabled) }
    },
    receiveFiles: { id, urls in
      await MainActor.run { FeatureRegistry.module(for: id)?.receiveFiles(urls) }
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
