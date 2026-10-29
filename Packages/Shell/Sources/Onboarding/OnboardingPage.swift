import Foundation
import VortexCore

/// A page of the onboarding, in its order (S12–S18): Welcome, Basics, one page per hard permission, the features' own
/// steps, Done.
enum OnboardingPage: Hashable, Sendable {
  case welcome
  /// Notifications and the login item, which macOS grants in place (S13).
  case basics
  /// Accessibility, Screen Recording or the pasteboard, which need System Settings (S14).
  case permission(Permission)
  /// A feature's own step (S17).
  case step(FeatureID)
  case done

  /// How the page is saved in onboarding.json and named in QA: `welcome`, `basics`, `permission:accessibility`,
  /// `step:secrets`, `done`.
  var id: String {
    switch self {
    case .welcome: "welcome"
    case .basics: "basics"
    case let .permission(permission): "permission:\(permission.rawValue)"
    case let .step(feature): "step:\(feature)"
    case .done: "done"
    }
  }

  init?(id: String) {
    switch id {
    case "welcome": self = .welcome
    case "basics": self = .basics
    case "done": self = .done
    default:
      if id.hasPrefix("permission:"), let permission = Permission(rawValue: String(id.dropFirst("permission:".count))) {
        self = .permission(permission)
      } else if id.hasPrefix("step:"), id.count > "step:".count {
        self = .step(String(id.dropFirst("step:".count)))
      } else {
        return nil
      }
    }
  }

  /// The page that holds a permission's row: Basics for notifications, its own page otherwise.
  static func holding(_ permission: Permission) -> OnboardingPage {
    permission.isGrantedInPlace ? .basics : .permission(permission)
  }
}

/// What a permission's checkbox shows (S2, S68, S72).
enum PermissionRowState: String, Equatable, Sendable, Encodable {
  /// Before the first read: no checkbox state (S72).
  case unknown
  case off
  case on
  /// On, with "Works after restart"; also the pasteboard once its pane was opened, "Checked after restart" (S68).
  case afterRestart
}
