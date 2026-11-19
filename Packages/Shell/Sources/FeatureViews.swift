import ComposableArchitecture
import FeatureRegistry
import SwiftUI
import VortexCore

/// The features' views, each made once, the first time the shell shows it. The shell asks only for the views of
/// features that run, so a feature the user hasn't added never has a view made and none of its code runs. Making one
/// is marked in the launch record: a crash inside it stops that feature next launch.
@MainActor
final class FeatureViews {
  static let shared = FeatureViews()

  @Dependency(\.launchGuard) private var launchGuard

  private var tabs: [FeatureID: AnyView] = [:]
  private var homeWidgets: [FeatureID: [HomeWidget]] = [:]
  private var utilityActions: [FeatureID: [UtilityAction]] = [:]
  private var settings: [FeatureID: AnyView?] = [:]
  private var onboardingSteps: [FeatureID: OnboardingStep?] = [:]

  /// The feature's tab; nil for a feature this build doesn't ship.
  func tab(_ id: FeatureID) -> AnyView? {
    cached(id, in: &tabs) { $0.makeTab() }
  }

  /// The feature's widgets on Home, none if it has none.
  func homeWidgets(_ id: FeatureID) -> [HomeWidget] {
    cached(id, in: &homeWidgets) { $0.makeHomeWidgets() } ?? []
  }

  /// The feature's utility actions, none if it has none.
  func utilityActions(_ id: FeatureID) -> [UtilityAction] {
    cached(id, in: &utilityActions) { $0.makeUtilityActions() } ?? []
  }

  /// The feature's own settings, if it has any: on its page in Settings › Features, after its tab's shortcut.
  func settings(_ id: FeatureID) -> AnyView? {
    cached(id, in: &settings) { $0.makeSettings() } ?? nil
  }

  /// The feature's own page in the onboarding, if it has one.
  func onboardingStep(_ id: FeatureID) -> OnboardingStep? {
    cached(id, in: &onboardingSteps) { $0.makeOnboardingStep() } ?? nil
  }

  private func cached<Value>(
    _ id: FeatureID,
    in cache: inout [FeatureID: Value],
    make: (any FeatureModule.Type) -> Value
  ) -> Value? {
    if let value = cache[id] { return value }
    guard let module = FeatureRegistry.module(for: id) else { return nil }
    var made: Value?
    launchGuard.around(id) { made = make(module) }
    guard let made else { return nil }
    cache[id] = made
    return made
  }
}
