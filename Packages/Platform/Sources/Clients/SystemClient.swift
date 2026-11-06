import AppKit
import ComposableArchitecture
import VortexCore

/// App-wide system settings: appearance, interface language, relaunch and quit.
@DependencyClient
public struct SystemClient: Sendable {
  public var applyTheme: @Sendable (_ theme: AppTheme) async -> Void
  /// The language chosen for Vortex; `.system` when it follows macOS.
  public var language: @Sendable () -> AppLanguage = { .system }
  /// Takes effect after a relaunch: macOS reads the language when the app starts.
  public var setLanguage: @Sendable (_ language: AppLanguage) -> Void
  /// Quits and opens the app again once this process is gone. If it is still there after about 10 s, as when the quit
  /// was cancelled, the app is not opened.
  public var relaunch: @Sendable () async -> Void
  /// Quits and opens the app at `app` once this process is gone, by the relaunch's helper with its 10 s limit: after
  /// Vortex moved itself to /Applications.
  public var relaunchFrom: @Sendable (_ app: URL) async -> Void
  public var quit: @Sendable () async -> Void
  /// Opens the app again once this process is gone, for a quit already under way, without quitting: the helper of
  /// `relaunch`, with its 10 s limit. `open` without `-n`, so a Vortex that someone else opened meanwhile is not
  /// doubled. Synchronous: it is called while the app terminates.
  public var reopenAfterQuit: @Sendable () -> Void
}

extension SystemClient: DependencyKey {
  public static let liveValue = SystemClient(
    applyTheme: { theme in
      await MainActor.run {
        NSApp.appearance = switch theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
      }
    },
    language: {
      // Only the app's own domain: the global AppleLanguages list is the system preference, not a choice for Vortex.
      let domain = Bundle.main.bundleIdentifier.flatMap(UserDefaults.standard.persistentDomain(forName:)) ?? [:]
      guard let code = (domain["AppleLanguages"] as? [String])?.first else { return .system }
      return AppLanguage.allCases.first { $0 != .system && code.hasPrefix($0.rawValue) } ?? .system
    },
    setLanguage: { language in
      if language == .system {
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
      } else {
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
      }
    },
    relaunch: {
      await MainActor.run {
        Relaunch.startHelper()
        NSApp.terminate(nil)
      }
    },
    relaunchFrom: { app in
      await MainActor.run {
        Relaunch.startHelper(bundlePath: app.path)
        NSApp.terminate(nil)
      }
    },
    quit: {
      await MainActor.run { NSApp.terminate(nil) }
    },
    reopenAfterQuit: {
      Relaunch.startHelper()
    }
  )

  public static let testValue = SystemClient()
}

/// The helper shell behind `relaunch`: it waits until this process exits, then opens the app again. It gives up after
/// `checks` looks 0.1 s apart, about 10 s, so a quit that was cancelled doesn't leave it waiting to reopen Vortex at the
/// next quit.
enum Relaunch {
  static let checks = 100

  /// Starts the helper for this process; it opens this app, or the one at `bundlePath`. It outlives the process: when
  /// Vortex exits, launchd adopts it.
  static func startHelper(bundlePath: String = Bundle.main.bundlePath) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = arguments(pid: ProcessInfo.processInfo.processIdentifier, bundlePath: bundlePath)
    try? task.run()
  }

  /// Arguments for `/bin/sh`. The bundle path goes in as `$0`, never into the script, so no path can break it.
  static func arguments(pid: pid_t, bundlePath: String) -> [String] {
    let script = "n=0; while kill -0 \(pid) 2>/dev/null; do n=$((n+1)); [ $n -gt \(checks) ] && exit 0; sleep 0.1; done; "
      + "open \"$0\""
    return ["-c", script, bundlePath]
  }
}

/// Who asked Vortex to quit, and whether Vortex comes back by itself afterwards.
///
/// A permission that works only after a relaunch, such as Screen Recording, makes System Settings offer «Quit & Reopen».
/// System Settings then quits Vortex with a Quit Apple event and opens it again about 3 s after it exits, but only while
/// System Settings itself still runs: closed before that, Vortex stays quit. So for that quit Vortex opens itself again
/// (`SystemClient.reopenAfterQuit`); `open` leaves a Vortex that System Settings opened first as it is.
public enum QuitRequest {
  /// System Settings' bundle id.
  public static let systemSettings = "com.apple.systempreferences"

  /// Whether a quit asked for by the app with this bundle id brings Vortex back: only System Settings'. Never a quit
  /// that isn't an Apple event (nil), as Vortex's own Quit and ⌘Q; never logout or shutdown (loginwindow), a newer
  /// Vortex taking over, or any other app.
  public static func reopens(senderBundleID: String?) -> Bool {
    senderBundleID == systemSettings
  }

  /// The bundle id of the app whose Quit Apple event Vortex is handling now; nil when the quit came another way. Read
  /// in `applicationShouldTerminate`, while the event is the current one.
  @MainActor
  public static func currentSenderBundleID() -> String? {
    guard let event = NSAppleEventManager.shared().currentAppleEvent,
          event.eventClass == AEEventClass(kCoreEventClass),
          event.eventID == AEEventID(kAEQuitApplication),
          let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value,
          pid > 0
    else { return nil }
    return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
  }
}

extension DependencyValues {
  public var systemClient: SystemClient {
    get { self[SystemClient.self] }
    set { self[SystemClient.self] = newValue }
  }
}
