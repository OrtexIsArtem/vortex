import AppKit
import ComposableArchitecture

/// Which app is in front, as macOS tells when apps come to the front and quit, and where an app's windows are: what a
/// panel needs to sit next to System Settings' window. Asks for no permission: window bounds need none, only titles do.
@DependencyClient
public struct ActiveAppClient: Sendable {
  /// The bundle id of each app that comes to the front from now on, Vortex included.
  public var activations: @Sendable () -> AsyncStream<String> = { .finished }
  /// The bundle id of each app that quits from now on.
  public var terminations: @Sendable () -> AsyncStream<String> = { .finished }
  /// The app in front now; nil when it has no bundle id.
  public var frontmost: @Sendable () async -> String? = { nil }
  /// The frames of the app's ordinary windows on the displays, front to back, in AppKit's screen coordinates (origin at
  /// the bottom left of the main display). Read off the main thread.
  public var windowFrames: @Sendable (_ bundleID: String) async -> [CGRect] = { _ in [] }
}

extension ActiveAppClient: DependencyKey {
  public static let liveValue = ActiveAppClient(
    activations: { apps(on: NSWorkspace.didActivateApplicationNotification) },
    terminations: { apps(on: NSWorkspace.didTerminateApplicationNotification) },
    frontmost: {
      await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    },
    windowFrames: { bundleID in
      let (pids, mainHeight) = await MainActor.run {
        (
          Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier)),
          NSScreen.screens.first?.frame.height ?? 0
        )
      }
      guard !pids.isEmpty else { return [] }
      let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
      return windowFrames(in: windows, pids: pids, mainDisplayHeight: mainHeight)
    }
  )

  public static let testValue = ActiveAppClient()

  /// The bundle ids NSWorkspace reports with `name`, as long as the stream lives.
  private static func apps(on name: Notification.Name) -> AsyncStream<String> {
    AsyncStream { continuation in
      let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: nil) { note in
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let bundleID = app?.bundleIdentifier { continuation.yield(bundleID) }
      }
      let token = UncheckedSendable(observer)
      continuation.onTermination = { _ in NSWorkspace.shared.notificationCenter.removeObserver(token.value) }
    }
  }

  /// The frames of the windows of `pids` at the ordinary level, front to back. Window lists measure from the top left of
  /// the main display, downwards; AppKit from its bottom left, upwards.
  static func windowFrames(in windows: [[String: Any]], pids: Set<pid_t>, mainDisplayHeight: CGFloat) -> [CGRect] {
    windows.compactMap { window -> CGRect? in
      guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
            window[kCGWindowLayer as String] as? Int == 0,
            let bounds = window[kCGWindowBounds as String] as? [String: Any],
            let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
      else { return nil }
      return CGRect(x: frame.minX, y: mainDisplayHeight - frame.maxY, width: frame.width, height: frame.height)
    }
  }
}

extension DependencyValues {
  public var activeAppClient: ActiveAppClient {
    get { self[ActiveAppClient.self] }
    set { self[ActiveAppClient.self] = newValue }
  }
}
