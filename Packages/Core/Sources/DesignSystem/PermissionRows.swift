import SwiftUI

/// Where a permission that a feature needs shows in that feature (S22, S40): nothing while it works or before the first
/// read, a yellow warning while it is off, and "Works after restart" once macOS granted it to the next launch.
public enum PermissionMark: String, Codable, Sendable {
  case warning
  case afterRestart

  /// The mark for a status; nil for granted, not needed, or unknown (no read yet: no flicker at launch, S22).
  public init?(_ status: PermissionStatus?) {
    switch status {
    case .notGranted?: self = .warning
    case .grantedAfterRestart?: self = .afterRestart
    case .granted?, .notNeeded?, nil: return nil
    }
  }
}

extension Collection<PermissionNeed> {
  /// The first of these permissions that is off: the one a sidebar dot names (S22.2, S39).
  public func firstOff(in statuses: [Permission: PermissionStatus]) -> Permission? {
    first { PermissionMark(statuses[$0.permission]) == .warning }?.permission
  }
}

/// A feature's settings rows for the permissions it needs (S22.3, S40), one per permission that isn't working yet:
/// - off: the title with a warning, the reason, and "Turn on", which opens the shell's page;
/// - granted for the next launch: "Works after restart" and "Restart Vortex", without yellow.
///
/// The feature re-reads the statuses when its section appears (S47).
public struct PermissionRows: View {
  private let needs: [PermissionNeed]
  private let statuses: [Permission: PermissionStatus]
  private let turnOn: (Permission) -> Void
  private let restart: () -> Void

  public init(
    _ needs: [PermissionNeed],
    statuses: [Permission: PermissionStatus],
    turnOn: @escaping (Permission) -> Void,
    restart: @escaping () -> Void
  ) {
    self.needs = needs
    self.statuses = statuses
    self.turnOn = turnOn
    self.restart = restart
  }

  public var body: some View {
    ForEach(needs, id: \.permission) { need in
      if let mark = PermissionMark(statuses[need.permission]) {
        row(need, mark)
      }
    }
  }

  @ViewBuilder
  private func row(_ need: PermissionNeed, _ mark: PermissionMark) -> some View {
    switch mark {
    case .warning:
      SettingsRow(
        title: Text(Image(systemName: "exclamationmark.triangle.fill")).foregroundStyle(VortexColor.warning)
          + Text(verbatim: " ") + Text(need.permission.title),
        caption: Text(need.reason)
      ) {
        Button {
          turnOn(need.permission)
        } label: {
          Text("Turn on", bundle: .module)
        }
        .buttonStyle(.quietCapsule)
      }
      .help(Text(need.permission.offLabel))
    case .afterRestart:
      SettingsRow(
        title: Text(need.permission.title),
        caption: Text("Works after restart", bundle: .module)
      ) {
        Button {
          restart()
        } label: {
          Text("Restart Vortex", bundle: .module)
        }
        .buttonStyle(.quietCapsule)
      }
    }
  }
}
