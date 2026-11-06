import ComposableArchitecture
import Foundation
import UserNotifications
import VortexCore

// The rules behind every status and request, apart from the system calls, so the live client and the simulated one
// follow the same rules and tests check them.

extension PermissionStatus {
  /// Notifications, from `UNNotificationSettings.authorizationStatus`: allowed, also quietly (provisional), is
  /// granted; not asked yet or denied is not. (`.ephemeral`, for App Clips, doesn't exist on macOS.)
  init(notifications: UNAuthorizationStatus) {
    switch notifications {
    case .authorized, .provisional: self = .granted
    default: self = .notGranted
    }
  }

  /// The pasteboard, from `NSPasteboard.general.accessBehavior` (nil before macOS 15.4, which has no such privacy).
  /// Only `.ask` and `.alwaysDeny` mean there is something to do. `.alwaysAllow` is what macOS 26.4 reports for an app
  /// while it doesn't enforce the privacy (seen on 26.6.2 too), so it can't tell a grant
  /// from no need, and `.default` is an app macOS never asked: both are `notNeeded`, and the pasteboard shows nowhere.
  /// The value stays as it was at launch until Vortex relaunches.
  init(pasteboard: PasteboardAccess?) {
    switch pasteboard {
    case .ask?, .alwaysDeny?: self = .notGranted
    case .default?, .alwaysAllow?, nil: self = .notNeeded
    }
  }
}

/// `NSPasteboard.AccessBehavior` (macOS 15.4), by a name the simulator and tests can use on any system.
enum PasteboardAccess: String, Codable, Sendable {
  case `default`, ask, alwaysAllow, alwaysDeny
}

/// One step of a request.
enum PermissionRequestStep: Equatable, Sendable {
  /// macOS's own prompt, then the pane if macOS shows nothing (`PromptWatch`): it doesn't for an app it lists already,
  /// as after an upgrade, a reinstall or with another build, nor for notifications it asked about once, and the click
  /// would otherwise do nothing.
  case promptOrSettings
  /// The permission's pane in System Settings.
  case openSettings
}

extension Permission {
  /// What a request does: macOS's own prompt the first time, the pane in System Settings after that, never both on a
  /// first request. `askedBefore`: Vortex requested this permission before (`AskedPermissions`).
  /// `notificationsDetermined`: the user has answered macOS about notifications, either way.
  func requestSteps(askedBefore: Bool, notificationsDetermined: Bool) -> [PermissionRequestStep] {
    switch self {
    case .notifications:
      // A second request may show nothing, as an unanswered prompt keeps it undetermined: the pane then, whatever the
      // status.
      askedBefore || notificationsDetermined ? [.openSettings] : [.promptOrSettings]
    case .accessibility, .screenRecording:
      askedBefore ? [.openSettings] : [.promptOrSettings]
    case .pasteboard:
      // macOS has no request for it, only the pane.
      [.openSettings]
    }
  }

  /// Vortex remembers asking for it (`AskedPermissions`). The pasteboard has nothing to ask.
  var remembersRequests: Bool {
    self != .pasteboard
  }

  /// The permission's pane in System Settings; `bundleID` picks Vortex in the Notifications pane. The Privacy & Security
  /// anchors are not documented; macOS 26.4 has these.
  func settingsURL(bundleID: String) -> URL {
    let pane = switch self {
    case .notifications: "com.apple.Notifications-Settings.extension?id=\(bundleID)"
    case .accessibility: "com.apple.preference.security?Privacy_Accessibility"
    case .screenRecording: "com.apple.preference.security?Privacy_ScreenCapture"
    case .pasteboard: "com.apple.preference.security?Privacy_Pasteboard"
    }
    return URL(string: "x-apple.systempreferences:\(pane)")
      ?? URL(string: "x-apple.systempreferences:com.apple.preference.security")!
  }
}

/// The permissions Vortex has requested, kept in DataFolder/permissions.json, so QA mode's own data folder and
/// its resets cover it: macOS can't tell "not asked" from "denied", and a request after the first one opens System
/// Settings instead of the prompt. A file that is missing or can't be read counts as no request.
struct AskedPermissions: Sendable {
  let url: URL

  /// DataFolder/permissions.json, where DataFolder points at the moment of the call.
  static var inDataFolder: AskedPermissions {
    AskedPermissions(url: DataFolder.url.appending(path: "permissions.json"))
  }

  /// Read and write one at a time within the app.
  private static let lock = NSLock()

  private struct File: Codable {
    /// Raw names, so names a newer Vortex wrote survive.
    var asked: [String]
  }

  func contains(_ permission: Permission) -> Bool {
    Self.lock.withLock { load().contains(permission.rawValue) }
  }

  /// Every permission requested that this build knows.
  var all: Set<Permission> {
    Self.lock.withLock { Set(load().compactMap(Permission.init(rawValue:))) }
  }

  func insert(_ permission: Permission) {
    Self.lock.withLock {
      let asked = load()
      guard !asked.contains(permission.rawValue) else { return }
      try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? JSONEncoder().encode(File(asked: asked + [permission.rawValue])).write(to: url, options: .atomic)
    }
  }

  private func load() -> [String] {
    guard let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) else {
      return []
    }
    return file.asked
  }
}

/// Whether macOS showed something after a request: if not, the request opens the pane.
enum PromptWatch {
  /// The app that shows macOS's alert for Accessibility, Screen Recording and Input Monitoring (macOS 26.4,
  /// /System/Library/PrivateFrameworks/UniversalAccess.framework/…/universalAccessAuthWarn.app).
  static let alertApp = "com.apple.accessibility.universalAccessAuthWarn"
  /// The alert app, and System Settings, which the alert's «Open System Settings» brings up.
  static let promptApps: Set<String> = [alertApp, "com.apple.systempreferences"]

  /// Accessibility, Screen Recording: true as soon as one of `promptApps` arrives in `apps` (the bundle ids of apps
  /// launched or activated). When `timeout` passes first, `alertIsShowing` decides: the alert app may be running
  /// already from an earlier request, or show its alert without becoming active.
  static func comesUp(
    _ apps: AsyncStream<String>,
    within timeout: Duration,
    alertIsShowing: @Sendable () async -> Bool
  ) async -> Bool {
    let arrived = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        for await app in apps where promptApps.contains(app) {
          return true
        }
        return false
      }
      group.addTask {
        try? await Task.sleep(for: timeout)
        return false
      }
      let arrived = await group.next() ?? false
      group.cancelAll()
      return arrived
    }
    if arrived { return true }
    return await alertIsShowing()
  }

  /// The alert is on screen: a window on screen belongs to the alert app. `kCGWindowOwnerPID` needs no permission.
  static func alertIsUp(_ windowsOnScreen: [ListedWindow], alertApps: Set<pid_t>) -> Bool {
    windowsOnScreen.contains { alertApps.contains($0.ownerPID) }
  }

  /// Notifications: `requestAuthorization` waits for the answer while its prompt shows. Back within about 1 s with
  /// macOS still undetermined, it showed nothing.
  static func notificationsShowedNothing(returnedQuickly: Bool, authorization: UNAuthorizationStatus) -> Bool {
    returnedQuickly && authorization == .notDetermined
  }
}

/// Work that may never end, given a time limit.
enum Deadline {
  /// The work's result, or nil when `limit` passes first. The work goes on in the background either way.
  static func result<T: Sendable>(
    within limit: Duration,
    _ work: @escaping @Sendable () async -> T
  ) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
      let pending = LockIsolated<CheckedContinuation<T?, Never>?>(continuation)
      @Sendable func finish(_ result: T?) {
        pending.withValue { continuation in
          continuation?.resume(returning: result)
          continuation = nil
        }
      }
      Task { finish(await work()) }
      Task {
        try? await Task.sleep(for: limit)
        finish(nil)
      }
    }
  }
}

// MARK: - Screen Recording

/// A window as `CGWindowListCopyWindowInfo` lists it: what Screen Recording shows in.
struct ListedWindow: Equatable, Sendable {
  var ownerPID: pid_t
  var layer: Int
  /// `kCGWindowName`. Without Screen Recording macOS leaves it out for other apps' windows; with it, an untitled
  /// window has an empty one.
  var name: String?
  /// The owner is an ordinary app with a Dock icon (`activationPolicy == .regular`), not a system agent.
  var ownerIsRegularApp: Bool
}

/// What other apps' windows tell about Screen Recording.
enum WindowTitles: Equatable, Sendable {
  /// Another app's window has a title: macOS shows titles to Vortex, so it has the permission.
  case visible
  /// Other apps' windows have no title at all, not even an empty one: macOS hides them.
  case hidden
  /// Nothing to tell by: no ordinary window of another app on screen, or only untitled ones.
  case unknown

  /// Only ordinary windows (layer 0) of other ordinary apps count: some system windows on other layers keep their
  /// titles without the permission (AltTab), and Vortex's own always have theirs.
  init(_ windows: [ListedWindow], ownPID: pid_t) {
    let others = windows.filter { $0.ownerPID != ownPID && $0.layer == 0 && $0.ownerIsRegularApp }
    if others.contains(where: { !($0.name ?? "").isEmpty }) {
      self = .visible
    } else if !others.isEmpty, others.allSatisfy({ $0.name == nil }) {
      self = .hidden
    } else {
      self = .unknown
    }
  }
}

/// Screen Recording as this process can use it. `CGPreflightScreenCaptureAccess()` keeps answering what was so at
/// launch, so after launch a grant shows as other apps' titles becoming visible, confirmed by one probe with
/// ScreenCaptureKit, which tells whether capture works now or only after a relaunch.
///
/// The probe runs only after Vortex itself has requested Screen Recording: it prompts if Vortex isn't listed,
/// and titles alone must never lead to a prompt, should macOS ever show them without the permission. Until then,
/// titles leave a `notGranted` status as it is; the grant shows after a relaunch, or after a request.
struct ScreenRecordingDetector: Equatable, Sendable {
  private(set) var status: PermissionStatus
  /// Titles were visible since the status turned on, so their disappearing means the user turned it off.
  private var sawTitles = false

  /// `grantedAtLaunch`: what `CGPreflightScreenCaptureAccess()` answers.
  init(grantedAtLaunch: Bool) {
    status = grantedAtLaunch ? .granted : .notGranted
  }

  /// The titles show a grant to confirm: probe once, then pass the result to `update`. `asked`: Vortex has requested
  /// Screen Recording (`AskedPermissions`).
  func needsProbe(_ titles: WindowTitles, asked: Bool) -> Bool {
    titles == .visible && status == .notGranted && asked
  }

  /// Takes in what the windows show, and after `needsProbe` whether capture worked.
  mutating func update(_ titles: WindowTitles, asked: Bool, probeSucceeded: Bool = false) {
    switch titles {
    case .visible:
      if status == .notGranted {
        guard asked else { return }
        status = probeSucceeded ? .granted : .grantedAfterRestart
      }
      sawTitles = true
    case .hidden:
      // A grant from launch stays until its titles have been seen: before that, hidden titles may only mean that
      // other apps have no titled window yet.
      guard sawTitles else { return }
      status = .notGranted
      sawTitles = false
    case .unknown:
      break
    }
  }
}
