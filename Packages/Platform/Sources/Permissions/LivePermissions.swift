import AppKit
import ApplicationServices
import ComposableArchitecture
import ScreenCaptureKit
import UserNotifications
import VortexCore

/// The live statuses: read from macOS without ever prompting (S5), and read again on the signals that may change them
/// while someone listens (S3). Nothing here runs under `swift test`: UNUserNotificationCenter needs an app bundle.
actor LivePermissions {
  typealias Statuses = [Permission: PermissionStatus]

  static let shared = LivePermissions()

  /// Wakes the read loop. Wake-ups that come during a read make one more read after it, so reads never overlap and a
  /// burst of signals costs one read.
  private nonisolated let wakeUps: AsyncStream<Void>.Continuation
  private var screenRecording: ScreenRecordingDetector?
  /// The last statuses read; listeners hear only changes.
  private var latest: Statuses?
  private var listeners: [UUID: AsyncStream<Statuses>.Continuation] = [:]
  /// Callers of `statuses()` waiting for the next read.
  private var waitingForRead: [CheckedContinuation<Statuses, Never>] = []
  private var isWatching = false
  private var frequentChecks: Task<Void, Never>?

  private init() {
    let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    wakeUps = continuation
    Task { await self.readLoop(stream) }
  }

  /// Reads every status now.
  func statuses() async -> Statuses {
    await withCheckedContinuation { continuation in
      waitingForRead.append(continuation)
      wakeUps.yield()
    }
  }

  /// The statuses now, and again on every change. Watches macOS's signals from the first listener on.
  nonisolated func updates() -> AsyncStream<Statuses> {
    let (stream, continuation) = AsyncStream.makeStream(of: Statuses.self, bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    continuation.onTermination = { _ in
      Task { await LivePermissions.shared.removeListener(id) }
    }
    Task { await self.addListener(id, continuation) }
    return stream
  }

  /// Reads once a second while a permission window is visible (S3); nowhere else.
  func setFrequentChecks(_ isOn: Bool) {
    frequentChecks?.cancel()
    frequentChecks = nil
    guard isOn else { return }
    wakeUps.yield()
    frequentChecks = Task { [wakeUps] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        wakeUps.yield()
      }
    }
  }

  /// Asks for a permission (S4, S48, S67): macOS's own prompt the first time, its pane in System Settings after that.
  /// Returns without waiting for the user's answer.
  nonisolated func request(_ permission: Permission) async {
    let asked = AskedPermissions.inDataFolder
    let askedBefore = asked.contains(permission)
    if permission.remembersRequests { asked.insert(permission) }
    let notificationsDetermined = permission == .notifications && !askedBefore
      ? await Self.notificationsAuthorization() != .notDetermined
      : true
    for step in permission.requestSteps(askedBefore: askedBefore, notificationsDetermined: notificationsDetermined) {
      switch step {
      case .prompt:
        // The answer comes whenever the user gives it, maybe never: read again then.
        Task { [wakeUps] in
          _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
          wakeUps.yield()
        }
      case .promptOrSettings:
        if await !Self.promptComesUp(for: permission) {
          await Self.openSettings(permission)
        }
      case .openSettings:
        await Self.openSettings(permission)
      }
    }
    wakeUps.yield()
  }

  /// Reads again now (S47); listeners hear of a change.
  func refresh() async {
    _ = await statuses()
  }

  static func openSettings(_ permission: Permission) async {
    let url = permission.settingsURL(bundleID: Bundle.main.bundleIdentifier ?? "io.github.ortexisartem.vortex")
    await MainActor.run { _ = NSWorkspace.shared.open(url) }
  }

  // MARK: - Reading

  private func readLoop(_ signals: AsyncStream<Void>) async {
    for await _ in signals {
      let callers = waitingForRead
      waitingForRead = []
      let statuses = await read()
      publish(statuses)
      for caller in callers {
        caller.resume(returning: statuses)
      }
    }
  }

  private func read() async -> Statuses {
    [
      .notifications: PermissionStatus(notifications: await Self.notificationsAuthorization()),
      .accessibility: AXIsProcessTrusted() ? .granted : .notGranted,
      .screenRecording: await readScreenRecording(),
      .pasteboard: PermissionStatus(pasteboard: Self.pasteboardAccess()),
    ]
  }

  private func readScreenRecording() async -> PermissionStatus {
    // The first read is at launch, so the preflight answers for the launch: it never changes in this process.
    var detector = screenRecording ?? ScreenRecordingDetector(grantedAtLaunch: CGPreflightScreenCaptureAccess())
    let titles = WindowTitles(Self.listedWindows(), ownPID: getpid())
    // The file is read only when titles show a grant to confirm.
    let asked = titles == .visible && detector.status == .notGranted
      && AskedPermissions.inDataFolder.contains(.screenRecording)
    let captureWorks = detector.needsProbe(titles, asked: asked) ? await Self.screenCaptureWorks() : false
    detector.update(titles, asked: asked, probeSucceeded: captureWorks)
    screenRecording = detector
    return detector.status
  }

  private func publish(_ statuses: Statuses) {
    guard statuses != latest else { return }
    latest = statuses
    for listener in listeners.values {
      listener.yield(statuses)
    }
  }

  private func addListener(_ id: UUID, _ continuation: AsyncStream<Statuses>.Continuation) {
    listeners[id] = continuation
    if let latest { continuation.yield(latest) }
    watch()
    wakeUps.yield()
  }

  private func removeListener(_ id: UUID) {
    listeners[id] = nil
  }

  /// Reads again on macOS's permission-change signal, after Accessibility's own one, and whenever an app becomes
  /// active, Vortex included (S3). The observers stay for the life of the app.
  private func watch() {
    guard !isWatching else { return }
    isWatching = true
    // tccd posts it after every change of a privacy permission. It says only that something changed.
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(),
      { _, _, _, _, _ in LivePermissions.shared.wakeUp() },
      "com.apple.tcc.access.changed" as CFString,
      nil,
      .deliverImmediately
    )
    // System Settings posts it before tccd writes the change, and `AXIsProcessTrusted` answers from a cache it
    // refreshes, so the read waits a moment, as Loop does.
    _ = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name("com.apple.accessibility.api"),
      object: nil,
      queue: nil
    ) { _ in LivePermissions.shared.wakeUp(after: .milliseconds(250)) }
    _ = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: nil
    ) { _ in LivePermissions.shared.wakeUp() }
    _ = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: nil
    ) { _ in LivePermissions.shared.wakeUp() }
  }

  nonisolated func wakeUp() {
    wakeUps.yield()
  }

  nonisolated func wakeUp(after delay: Duration) {
    Task { [wakeUps] in
      try? await Task.sleep(for: delay)
      wakeUps.yield()
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

  /// Whether ScreenCaptureKit gives this process the screen's content now; false after 5 s without an answer.
  private static func screenCaptureWorks() async -> Bool {
    await withCheckedContinuation { continuation in
      let answer = LockIsolated<CheckedContinuation<Bool, Never>?>(continuation)
      @Sendable func finish(_ works: Bool) {
        answer.withValue { continuation in
          continuation?.resume(returning: works)
          continuation = nil
        }
      }
      Task {
        let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        finish(content != nil)
      }
      Task {
        try? await Task.sleep(for: .seconds(5))
        finish(false)
      }
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
  /// macOS's alert or System Settings came up within about 1.5 s (S67).
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
    return await PromptWatch.comesUp(apps, within: .milliseconds(1500))
  }
}
