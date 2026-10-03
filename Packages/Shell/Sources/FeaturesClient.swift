import ComposableArchitecture
import FeatureRegistry
import VortexCore

/// Lets ShellFeature reach the feature modules without knowing their types.
@DependencyClient
struct FeaturesClient: Sendable {
  /// Starts or stops the background work of a feature, see `FeatureModule.setEnabled`.
  var setEnabled: @Sendable (_ id: FeatureID, _ isEnabled: Bool) async -> Void
}

extension FeaturesClient: DependencyKey {
  static let liveValue = FeaturesClient(
    setEnabled: { id, isEnabled in
      await MainActor.run { FeatureRegistry.module(for: id)?.setEnabled(isEnabled) }
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
