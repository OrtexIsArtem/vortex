import ComposableArchitecture
import ServiceManagement

/// Starting Vortex at login, through the system login items.
@DependencyClient
public struct LaunchAtLoginClient: Sendable {
  public var isEnabled: @Sendable () -> Bool = { false }
  public var setEnabled: @Sendable (_ isEnabled: Bool) throws -> Void
  /// Turns launch at login on for the first launch of a release build. Debug builds are left alone,
  /// so a build from Xcode never registers itself as a login item.
  public var enableByDefault: @Sendable () -> Void
}

extension LaunchAtLoginClient: DependencyKey {
  public static let liveValue = LaunchAtLoginClient(
    isEnabled: { SMAppService.mainApp.status == .enabled },
    setEnabled: { isEnabled in
      if isEnabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    },
    enableByDefault: {
      #if !DEBUG
        try? SMAppService.mainApp.register()
      #endif
    }
  )

  public static let testValue = LaunchAtLoginClient()
}

extension DependencyValues {
  public var launchAtLoginClient: LaunchAtLoginClient {
    get { self[LaunchAtLoginClient.self] }
    set { self[LaunchAtLoginClient.self] = newValue }
  }
}
