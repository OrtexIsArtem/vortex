import ComposableArchitecture

/// The notch, the window and the menu bar icon, as seen by ShellFeature.
/// Internal to the shell: features never open or close the window themselves.
@DependencyClient
struct WindowClient: Sendable {
  var events: @Sendable () async -> AsyncStream<WindowEvent> = { .finished }
  var present: @Sendable (_ reason: OpenReason) async -> Void
  var dismiss: @Sendable () async -> Void
  var setMenuBarIconVisible: @Sendable (_ isVisible: Bool) async -> Void
}

extension WindowClient: DependencyKey {
  static let liveValue = WindowClient(
    events: { await WindowController.shared.events() },
    present: { reason in await WindowController.shared.present(reason) },
    dismiss: { await WindowController.shared.dismiss() },
    setMenuBarIconVisible: { isVisible in await WindowController.shared.setMenuBarIconVisible(isVisible) }
  )

  static let testValue = WindowClient()
}

extension DependencyValues {
  var windowClient: WindowClient {
    get { self[WindowClient.self] }
    set { self[WindowClient.self] = newValue }
  }
}
