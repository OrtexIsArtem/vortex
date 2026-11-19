import Foundation
import VortexCore
import VortexPlatform

/// The onboarding's configuration, in one place.
enum OnboardingConfig {
  /// Permissions Vortex can't be used without. One counts only while an enabled feature or the shell needs it.
  /// None for now; QA mode may change the shell's copy per run, `ShellFeature.State.requiredPermissions`.
  static let requiredPermissions: Set<Permission> = []

  /// Release builds apply "Open at login" when the user leaves Basics, and so do QA runs with release behavior; debug
  /// builds never register themselves.
  static var appliesLoginItem: Bool {
    #if DEBUG
      QA.releaseBehavior
    #else
      true
    #endif
  }
}

/// The permissions Vortex needs now and why: what the enabled features and utilities declare, as keyboard cleaning
/// declares Accessibility.
struct PermissionCatalog: Equatable, Sendable {
  struct Need: Equatable, Sendable {
    /// The feature or utility that needs it.
    var feature: FeatureID
    var reason: LocalizedStringResource
  }

  struct Entry: Equatable, Sendable {
    var permission: Permission
    /// Every feature that needs it, in sidebar order.
    var needs: [Need]
    /// Configured as required, and needed.
    var isRequired: Bool

    var reasons: [LocalizedStringResource] { needs.map(\.reason) }
  }

  /// One entry for each permission something needs, in the order of `Permission.allCases`: notifications,
  /// Accessibility, Screen Recording, the pasteboard.
  var entries: [Entry]

  /// `features`: the enabled ones, in sidebar order. `required`: the configured set, `OnboardingConfig`.
  init(features: [FeatureDescriptor], required: Set<Permission>) {
    let needs = features.flatMap { feature in
      feature.permissionNeeds.map { (permission: $0.permission, need: Need(feature: feature.id, reason: $0.reason)) }
    }
    entries = Permission.allCases.compactMap { permission in
      let needs = needs.filter { $0.permission == permission }.map(\.need)
      return needs.isEmpty ? nil : Entry(permission: permission, needs: needs, isRequired: required.contains(permission))
    }
  }

  func entry(for permission: Permission) -> Entry? {
    entries.first { $0.permission == permission }
  }

  /// The required permissions macOS says are off, in the catalog's order. A status not read yet doesn't count, nor does
  /// `notNeeded`; `grantedAfterRestart` counts as on.
  func missingRequired(_ statuses: [Permission: PermissionStatus]) -> [Permission] {
    entries.filter { $0.isRequired && statuses[$0.permission] == .notGranted }.map(\.permission)
  }
}
