import ComposableArchitecture

/// The notch, the window and the menu bar icon, as seen by ShellFeature.
/// Internal to the shell: features never open or close the window themselves.
@DependencyClient
struct WindowClient: Sendable {
  var events: @Sendable () async -> AsyncStream<WindowEvent> = { .finished }
  var present: @Sendable (_ reason: OpenReason) async -> Void
  var dismiss: @Sendable () async -> Void
  var setMenuBarIconVisible: @Sendable (_ isVisible: Bool) async -> Void
  /// Whether files may be dropped on the menu bar icon: only while some feature takes them.
  var setAcceptsFiles: @Sendable (_ acceptsFiles: Bool) async -> Void
}

extension WindowClient: DependencyKey {
  static let liveValue = WindowClient(
    events: { await WindowController.shared.events() },
    present: { reason in await WindowController.shared.present(reason) },
    dismiss: { await WindowController.shared.dismiss() },
    setMenuBarIconVisible: { isVisible in await WindowController.shared.setMenuBarIconVisible(isVisible) },
    setAcceptsFiles: { acceptsFiles in await WindowController.shared.setAcceptsFiles(acceptsFiles) }
  )

  static let testValue = WindowClient()
}

extension DependencyValues {
  var windowClient: WindowClient {
    get { self[WindowClient.self] }
    set { self[WindowClient.self] = newValue }
  }
}
