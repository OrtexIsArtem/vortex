import SwiftUI

/// Where a permission that a feature needs shows in that feature: nothing while it works or before the first
/// read, a yellow warning while it is off, and "Works after restart" once macOS granted it to the next launch.
public enum PermissionMark: String, Codable, Sendable {
  case warning
  case afterRestart

  /// The mark for a status; nil for granted, not needed, or unknown (no read yet: no flicker at launch).
  public init?(_ status: PermissionStatus?) {
    switch status {
    case .notGranted?: self = .warning
    case .grantedAfterRestart?: self = .afterRestart
    case .granted?, .notNeeded?, nil: return nil
    }
  }
}

extension Collection<PermissionNeed> {
  /// The first of these permissions that is off: the one a sidebar dot names.
  public func firstOff(in statuses: [Permission: PermissionStatus]) -> Permission? {
    first { PermissionMark(statuses[$0.permission]) == .warning }?.permission
  }
}

/// A feature's settings rows for the permissions it needs, one per permission that isn't working yet:
/// - off: the title with a warning, the reason, and "Turn on", which opens the shell's page;
/// - granted for the next launch: "Works after restart" and "Restart Vortex", without yellow.
///
/// The feature re-reads the statuses when its section appears. A feature's page in the catalog shows its permissions
/// with the same pieces: `PermissionNeed.title(_:)`, `caption(_:)`, `PermissionButton` and `permissionHelp(_:_:)`.
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
        SettingsRow(title: need.title(mark), caption: need.caption(mark)) {
          PermissionButton(need.permission, mark: mark, turnOn: turnOn, restart: restart)
        }
        .permissionHelp(need, mark)
      }
    }
  }
}

extension PermissionNeed {
  /// The permission's name as a feature's rows show it, after a yellow warning while it is off.
  public func title(_ mark: PermissionMark?) -> Text {
    guard mark == .warning else { return Text(permission.title) }
    return Text(Image(systemName: "exclamationmark.triangle.fill")).foregroundStyle(VortexColor.warning)
      + Text(verbatim: " ") + Text(permission.title)
  }

  /// Why the feature needs it; "Works after restart" once macOS granted it to the next launch.
  public func caption(_ mark: PermissionMark?) -> Text {
    mark == .afterRestart ? Text("Works after restart", bundle: .module) : Text(reason)
  }
}

/// What a feature's row offers for a permission that isn't working yet: "Turn on", which opens the shell's page, or
/// "Restart Vortex" once macOS granted it to the next launch.
public struct PermissionButton: View {
  private let permission: Permission
  private let mark: PermissionMark
  private let turnOn: (Permission) -> Void
  private let restart: () -> Void

  public init(
    _ permission: Permission,
    mark: PermissionMark,
    turnOn: @escaping (Permission) -> Void,
    restart: @escaping () -> Void
  ) {
    self.permission = permission
    self.mark = mark
    self.turnOn = turnOn
    self.restart = restart
  }

  public var body: some View {
    switch mark {
    case .warning:
      Button {
        turnOn(permission)
      } label: {
        Text("Turn on", bundle: .module)
      }
      .buttonStyle(.quietCapsule)
    case .afterRestart:
      Button {
        restart()
      } label: {
        Text("Restart Vortex", bundle: .module)
      }
      .buttonStyle(.quietCapsule)
    }
  }
}

extension View {
  /// A permission's row says "Notifications are off" as its tooltip while the permission is off.
  @ViewBuilder
  public func permissionHelp(_ need: PermissionNeed, _ mark: PermissionMark?) -> some View {
    if mark == .warning {
      help(Text(need.permission.offLabel))
    } else {
      self
    }
  }
}
