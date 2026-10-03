import ComposableArchitecture

/// The notch, the window and the menu bar icon, as seen by reducers.
@DependencyClient
public struct WindowClient: Sendable {
  public var events: @Sendable () async -> AsyncStream<WindowEvent> = { .finished }
  public var present: @Sendable (_ reason: OpenReason) async -> Void
  public var dismiss: @Sendable () async -> Void
  public var setMenuBarIconVisible: @Sendable (_ isVisible: Bool) async -> Void
  public var hasNotchedScreen: @Sendable () async -> Bool = { true }
}

extension WindowClient: DependencyKey {
  public static let liveValue = WindowClient(
    events: { await WindowController.shared.events() },
    present: { reason in await WindowController.shared.present(reason) },
    dismiss: { await WindowController.shared.dismiss() },
    setMenuBarIconVisible: { isVisible in await WindowController.shared.setMenuBarIconVisible(isVisible) },
    hasNotchedScreen: { await WindowController.shared.hasNotchedScreen }
  )

  public static let testValue = WindowClient()
}

extension DependencyValues {
  public var windowClient: WindowClient {
    get { self[WindowClient.self] }
    set { self[WindowClient.self] = newValue }
  }
}
