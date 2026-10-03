import ComposableArchitecture
import Foundation
import ServiceManagement

public enum LaunchAtLoginStatus: Equatable, Sendable {
  case enabled
  case disabled
  /// Registered, but the user has to allow it in System Settings › General › Login Items.
  case requiresApproval
}

/// Starting Vortex at login, through the system login items. Calls go to a system service, so they are async.
@DependencyClient
public struct LaunchAtLoginClient: Sendable {
  public var status: @Sendable () async -> LaunchAtLoginStatus = { .disabled }
  /// Turns launch at login on or off and returns the status that resulted.
  public var setEnabled: @Sendable (_ isEnabled: Bool) async -> LaunchAtLoginStatus = { _ in .disabled }
  /// Turns launch at login on once, on the first launch of a release build. Debug builds never register
  /// themselves and do not use up that first launch.
  public var enableOnFirstLaunch: @Sendable () async -> Void
  public var openSystemSettings: @Sendable () async -> Void
}

extension LaunchAtLoginClient: DependencyKey {
  public static let liveValue: LaunchAtLoginClient = {
    @Sendable func currentStatus() -> LaunchAtLoginStatus {
      switch SMAppService.mainApp.status {
      case .enabled: .enabled
      case .requiresApproval: .requiresApproval
      default: .disabled
      }
    }
    return LaunchAtLoginClient(
      status: { currentStatus() },
      setEnabled: { isEnabled in
        // A failure leaves the status as it was, which is what the switch then shows.
        if isEnabled {
          try? SMAppService.mainApp.register()
        } else {
          try? SMAppService.mainApp.unregister()
        }
        return currentStatus()
      },
      enableOnFirstLaunch: {
        #if !DEBUG
          let key = "launchAtLoginSetUp"
          guard !UserDefaults.standard.bool(forKey: key) else { return }
          UserDefaults.standard.set(true, forKey: key)
          try? SMAppService.mainApp.register()
        #endif
      },
      openSystemSettings: {
        SMAppService.openSystemSettingsLoginItems()
      }
    )
  }()

  public static let testValue = LaunchAtLoginClient()
}

extension DependencyValues {
  public var launchAtLoginClient: LaunchAtLoginClient {
    get { self[LaunchAtLoginClient.self] }
    set { self[LaunchAtLoginClient.self] = newValue }
  }
}
