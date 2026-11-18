import ComposableArchitecture
import VortexCore

/// The notch, the window and the menu bar icon, as seen by ShellFeature.
/// Internal to the shell: features never open or close the window themselves.
@DependencyClient
struct WindowClient: Sendable {
  var events: @Sendable () async -> AsyncStream<WindowEvent> = { .finished }
  var present: @Sendable (_ reason: OpenReason) async -> Void
  var dismiss: @Sendable () async -> Void
  /// Grows or shrinks the window, keeping its left edge; a closed window takes the size at its next open.
  var setSize: @Sendable (_ size: WindowSize) async -> Void
  var setMenuBarIconVisible: @Sendable (_ isVisible: Bool) async -> Void
  /// Whether files may be dropped on the menu bar icon: only while some feature takes them.
  var setAcceptsFiles: @Sendable (_ acceptsFiles: Bool) async -> Void
  /// For keyboard cleaning: Vortex in front, taking every key itself; see `WindowController.holdKeyboard`.
  var holdKeyboard: @Sendable (_ isHeld: Bool) async -> Void
  /// Features whose notch indicators don't show: those that don't run. Keys that are no feature's id always show.
  var setHiddenIndicatorOwners: @Sendable (_ owners: Set<FeatureID>) async -> Void
}

extension WindowClient: DependencyKey {
  static let liveValue = WindowClient(
    events: { await WindowController.shared.events() },
    present: { reason in await WindowController.shared.present(reason) },
    dismiss: { await WindowController.shared.dismiss() },
    setSize: { size in await WindowController.shared.setSize(size) },
    setMenuBarIconVisible: { isVisible in await WindowController.shared.setMenuBarIconVisible(isVisible) },
    setAcceptsFiles: { acceptsFiles in await WindowController.shared.setAcceptsFiles(acceptsFiles) },
    holdKeyboard: { isHeld in await WindowController.shared.holdKeyboard(isHeld) },
    setHiddenIndicatorOwners: { owners in await WindowController.shared.setHiddenIndicatorOwners(owners) }
  )

  static let testValue = WindowClient()
}

extension DependencyValues {
  var windowClient: WindowClient {
    get { self[WindowClient.self] }
    set { self[WindowClient.self] = newValue }
  }
}
