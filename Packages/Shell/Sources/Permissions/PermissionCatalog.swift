import Foundation
import VortexCore
import VortexPlatform

/// The onboarding's configuration, in one place (S30).
enum OnboardingConfig {
  /// Permissions Vortex can't be used without (S9). One counts only while an enabled feature or the shell needs it
  /// (S66). None for now; QA mode may change the shell's copy per run, `ShellFeature.State.requiredPermissions`.
  static let requiredPermissions: Set<Permission> = []

  /// Release builds apply "Open at login" when the user leaves Basics, and so do QA runs with release behavior; debug
  /// builds never register themselves (S13, S74).
  static var appliesLoginItem: Bool {
    #if DEBUG
      QA.releaseBehavior
    #else
      true
    #endif
  }
}

/// The permissions Vortex needs now and why (S29, S62): what the enabled features declare, plus the shell's own
/// Accessibility for keyboard cleaning, which counts only while Home, where its button is, is on (S54).
struct PermissionCatalog: Equatable, Sendable {
  /// Who needs a permission.
  enum Owner: Equatable, Sendable {
    case feature(FeatureID)
    /// The shell's keyboard cleaning, behind Home's keyboard button.
    case keyboardCleaning
  }

  struct Need: Equatable, Sendable {
    var owner: Owner
    var reason: LocalizedStringResource
  }

  struct Entry: Equatable, Sendable {
    var permission: Permission
    /// Everyone who needs it, features in sidebar order, keyboard cleaning last.
    var needs: [Need]
    /// Configured as required, and needed (S45, S66).
    var isRequired: Bool

    var reasons: [LocalizedStringResource] { needs.map(\.reason) }
  }

  /// Home shows the keyboard button (`EnvironmentValues.keyboardCleaning`).
  static let keyboardCleaningHost: FeatureID = "home"
  static let keyboardCleaningReason = LocalizedStringResource(
    "Locks the keyboard while you clean it.",
    bundle: .atURL(Bundle.module.bundleURL)
  )

  /// One entry for each permission something needs, in the order of `Permission.allCases`: notifications,
  /// Accessibility, Screen Recording, the pasteboard.
  var entries: [Entry]

  /// `features`: the enabled ones, in sidebar order. `required`: the configured set, `OnboardingConfig`.
  init(features: [FeatureDescriptor], required: Set<Permission>) {
    var needs = features.flatMap { feature in
      feature.permissionNeeds.map { (permission: $0.permission, need: Need(owner: .feature(feature.id), reason: $0.reason)) }
    }
    if features.contains(where: { $0.id == Self.keyboardCleaningHost }) {
      needs.append((.accessibility, Need(owner: .keyboardCleaning, reason: Self.keyboardCleaningReason)))
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
  /// `notNeeded`; `grantedAfterRestart` counts as on (S66, S82).
  func missingRequired(_ statuses: [Permission: PermissionStatus]) -> [Permission] {
    entries.filter { $0.isRequired && statuses[$0.permission] == .notGranted }.map(\.permission)
  }
}
