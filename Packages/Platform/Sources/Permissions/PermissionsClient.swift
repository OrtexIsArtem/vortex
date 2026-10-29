import ComposableArchitecture
import Foundation
import VortexCore

/// The macOS permissions Vortex needs: what macOS says about each, live, and asking for one. The shell reads and asks;
/// features read the statuses from `@Shared(.permissionStatuses)`, open the shell's page with
/// `@Dependency(\.permissionPage)`, and may call `refresh()` when a row about a permission appears (S47).
///
/// - Notifications: `getNotificationSettings`; authorized or provisional is `granted`.
/// - Accessibility: `AXIsProcessTrusted()`, read again 250 ms after macOS's `com.apple.accessibility.api`.
/// - Screen Recording: `CGPreflightScreenCaptureAccess()` at launch; after that other apps' window titles (see
///   `WindowTitles`), a new grant confirmed once by ScreenCaptureKit, and only after Vortex has requested it
///   (S58): working now is `granted`, not yet `grantedAfterRestart`.
/// - Pasteboard: `NSPasteboard.general.accessBehavior` on macOS 15.4+, fixed until a relaunch; `notGranted` only for
///   `.ask` and `.alwaysDeny`, otherwise `notNeeded`.
@DependencyClient
public struct PermissionsClient: Sendable {
  /// Every status, read now. Never prompts (S5).
  public var statuses: @Sendable () async -> [Permission: PermissionStatus] = { [:] }
  /// The full map now and on every change, never the same twice in a row (S3). Read again on macOS's
  /// permission-change signal, whenever an app becomes active, on `refresh()`, and once a second while frequent checks
  /// are on.
  public var updates: @Sendable () -> AsyncStream<[Permission: PermissionStatus]> = { .finished }
  /// Reads once a second while a permission window is visible; off, it doesn't poll.
  public var setFrequentChecks: @Sendable (_ on: Bool) async -> Void
  /// Asks for a permission (S4, S48, S67), without waiting for the user's answer:
  /// - Notifications: macOS's prompt while the user never answered and Vortex never asked, and the pane too if the
  ///   request comes back within about 1 s still unanswered, as macOS then showed nothing; otherwise the Notifications
  ///   pane of Vortex, whatever the status, as a second request may show nothing.
  /// - Accessibility, Screen Recording: the first time, macOS's request, and the pane if within about 1.5 s neither
  ///   macOS's alert nor System Settings came up (launched, activated, or with the alert's window on screen at the
  ///   end); after that, the pane.
  /// - Pasteboard: the pane; macOS has no request for it.
  ///
  /// What Vortex asked for is kept in DataFolder/permissions.json. After Vortex was removed from a list with "−", or a
  /// `tccutil reset`, macOS may prompt again while the pane opens: "never both at once" can't hold then (S59).
  public var request: @Sendable (_ permission: Permission) async -> Void
  /// Opens the permission's pane in System Settings.
  public var openSettings: @Sendable (_ permission: Permission) async -> Void
  /// Reads every status again now; `updates` tells of a change (S47). Notifications have no change signal, so the shell
  /// calls it when the notch window opens. Not polling.
  public var refresh: @Sendable () async -> Void
}

extension PermissionsClient: DependencyKey {
  public static let liveValue = PermissionsClient(
    statuses: { await LivePermissions.feed.statuses() },
    updates: { LivePermissions.updates() },
    setFrequentChecks: { isOn in LivePermissions.feed.setFrequentChecks(isOn) },
    request: { permission in await LivePermissions.request(permission) },
    openSettings: { permission in await LivePermissions.openSettings(permission) },
    refresh: { _ = await LivePermissions.feed.statuses() }
  )

  public static let testValue = PermissionsClient()
}

extension DependencyValues {
  public var permissionsClient: PermissionsClient {
    get { self[PermissionsClient.self] }
    set { self[PermissionsClient.self] = newValue }
  }
}
