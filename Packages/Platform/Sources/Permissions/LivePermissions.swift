import AppKit
import ApplicationServices
import ComposableArchitecture
import ScreenCaptureKit
import UserNotifications
import VortexCore

/// The live statuses: read from macOS without ever prompting (S5), through `PermissionFeed`, and read again on the
/// signals that may change them from the first listener on (S3). Nothing here runs under `swift test`:
/// UNUserNotificationCenter needs an app bundle.
enum LivePermissions {
  typealias Statuses = [Permission: PermissionStatus]

  static let feed = PermissionFeed(clock: ContinuousClock(), read: { await read() })

  /// Screen Recording across reads; the feed runs one read at a time.
  private static let screenRecording = LockIsolated<ScreenRecordingDetector?>(nil)

  /// The statuses now, and again on every change. Watches macOS's signals from the first listener on.
  static func updates() -> AsyncStream<Statuses> {
    _ = watching
    return feed.updates()
  }

  /// Asks for a permission (S4, S48, S67): macOS's own prompt the first time, its pane in System Settings after that,
  /// or at once when macOS shows nothing. Returns without waiting for the user's answer.
  static func request(_ permission: Permission) async {
    let asked = AskedPermissions.inDataFolder
    let askedBefore = asked.contains(permission)
    if permission.remembersRequests { asked.insert(permission) }
    let notificationsDetermined = permission == .notifications && !askedBefore
      ? await notificationsAuthorization() != .notDetermined
      : true
    for step in permission.requestSteps(askedBefore: askedBefore, notificationsDetermined: notificationsDetermined) {
      switch step {
      case .promptOrSettings:
        let cameUp = permission == .notifications
          ? await notificationsPromptComesUp()
          : await promptComesUp(for: permission)
        if !cameUp { await openSettings(permission) }
      case .openSettings:
        await openSettings(permission)
      }
    }
    feed.wakeUp()
  }

  static func openSettings(_ permission: Permission) async {
    let url = permission.settingsURL(bundleID: Bundle.main.bundleIdentifier ?? "io.github.ortexisartem.vortex")
    await MainActor.run { _ = NSWorkspace.shared.open(url) }
  }

  // MARK: - Reading

  private static func read() async -> Statuses {
    [
      .notifications: PermissionStatus(notifications: await notificationsAuthorization()),
      .accessibility: AXIsProcessTrusted() ? .granted : .notGranted,
      .screenRecording: await readScreenRecording(),
      .pasteboard: PermissionStatus(pasteboard: pasteboardAccess()),
    ]
  }

  private static func readScreenRecording() async -> PermissionStatus {
    // The first read is at launch, so the preflight answers for the launch: it never changes in this process.
    var detector = screenRecording.value ?? ScreenRecordingDetector(grantedAtLaunch: CGPreflightScreenCaptureAccess())
    let titles = WindowTitles(listedWindows(), ownPID: getpid())
    // The file is read only when titles show a grant to confirm.
    let asked = titles == .visible && detector.status == .notGranted
      && AskedPermissions.inDataFolder.contains(.screenRecording)
    let captureWorks = detector.needsProbe(titles, asked: asked)
      ? await Deadline.result(within: .seconds(5)) {
        (try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)) != nil
      } ?? false
      : false
    detector.update(titles, asked: asked, probeSucceeded: captureWorks)
    let updated = detector
    screenRecording.setValue(updated)
    return updated.status
  }

  // MARK: - Signals

  /// Reads again on macOS's permission-change signal, after Accessibility's own one, and whenever an app becomes
  /// active, Vortex included (S3). Set up once, for the life of the app.
  private static let watching: Void = {
    // tccd posts it after every change of a privacy permission. It says only that something changed.
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(feed).toOpaque(),
      { _, _, _, _, _ in LivePermissions.feed.wakeUp() },
      "com.apple.tcc.access.changed" as CFString,
      nil,
      .deliverImmediately
    )
    // Delivered at once also while Vortex is inactive, as it is while the user is in System Settings.
    DistributedNotificationCenter.default().addObserver(
      accessibilityObserver,
      selector: #selector(AccessibilityObserver.accessibilityChanged(_:)),
      name: Notification.Name("com.apple.accessibility.api"),
      object: nil,
      suspensionBehavior: .deliverImmediately
    )
    _ = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: nil
    ) { _ in LivePermissions.feed.wakeUp() }
    _ = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: nil
    ) { _ in LivePermissions.feed.wakeUp() }
  }()

  private static let accessibilityObserver = AccessibilityObserver()

  /// System Settings posts `com.apple.accessibility.api` before tccd writes the change, and `AXIsProcessTrusted`
  /// answers from a cache it refreshes, so the read waits a moment, as Loop does.
  private final class AccessibilityObserver: NSObject, Sendable {
    @objc func accessibilityChanged(_ notification: Notification) {
      LivePermissions.feed.wakeUp(after: .milliseconds(250))
    }
  }

  // MARK: - macOS

  private static func notificationsAuthorization() async -> UNAuthorizationStatus {
    await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
  }

  /// Every window on screen with its owner, layer and title. Needs no permission; titles come only with Screen
  /// Recording.
  private static func listedWindows() -> [ListedWindow] {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] ?? []
    var regularApps: [pid_t: Bool] = [:]
    return windows.compactMap { window in
      guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
            let layer = window[kCGWindowLayer as String] as? Int
      else { return nil }
      let isRegular = regularApps[pid] ?? {
        let isRegular = NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
        regularApps[pid] = isRegular
        return isRegular
      }()
      return ListedWindow(
        ownerPID: pid,
        layer: layer,
        name: window[kCGWindowName as String] as? String,
        ownerIsRegularApp: isRegular
      )
    }
  }

  private static func pasteboardAccess() -> PasteboardAccess? {
    guard #available(macOS 15.4, *) else { return nil }
    return switch NSPasteboard.general.accessBehavior {
    case .ask: .ask
    case .alwaysAllow: .alwaysAllow
    case .alwaysDeny: .alwaysDeny
    case .default: .default
    @unknown default: .default
    }
  }

  /// Calls macOS's request for Accessibility or Screen Recording, without waiting for the answer, and tells whether
  /// macOS's alert or System Settings came up within about 1.5 s (S67): launched or activated meanwhile, or, at the
  /// end, a window of the alert app on screen.
  private static func promptComesUp(for permission: Permission) async -> Bool {
    let (apps, continuation) = AsyncStream.makeStream(of: String.self)
    let center = NSWorkspace.shared.notificationCenter
    // Watched before the call, so an alert that comes up at once is seen.
    let observers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification].map {
      center.addObserver(forName: $0, object: nil, queue: nil) { notification in
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let id = app?.bundleIdentifier { continuation.yield(id) }
      }
    }
    defer {
      for observer in observers {
        center.removeObserver(observer)
      }
      continuation.finish()
    }
    switch permission {
    case .accessibility:
      await MainActor.run {
        // By name: `kAXTrustedCheckOptionPrompt` is a mutable global, which strict concurrency won't read.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
      }
    case .screenRecording:
      // `CGRequestScreenCaptureAccess()` is unreliable on macOS 15 and later; asking ScreenCaptureKit for the screen's
      // content prompts while Vortex isn't listed.
      Task { _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
    case .notifications, .pasteboard:
      return false
    }
    return await PromptWatch.comesUp(apps, within: .milliseconds(1500)) {
      let alert = NSRunningApplication.runningApplications(withBundleIdentifier: PromptWatch.alertApp)
      return PromptWatch.alertIsUp(listedWindows(), alertApps: Set(alert.map(\.processIdentifier)))
    }
  }

  /// Calls macOS's request for notifications. `requestAuthorization` waits for the answer while its prompt shows, and
  /// returns at once when macOS shows nothing, as after a prompt that was never answered (S48): then nothing came up.
  private static func notificationsPromptComesUp() async -> Bool {
    let returned: Void? = await Deadline.result(within: .seconds(1)) {
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
      // The answer, whenever it comes.
      feed.wakeUp()
    }
    let returnedQuickly = returned != nil
    let authorization = returnedQuickly ? await notificationsAuthorization() : .notDetermined
    return !PromptWatch.notificationsShowedNothing(returnedQuickly: returnedQuickly, authorization: authorization)
  }
}
