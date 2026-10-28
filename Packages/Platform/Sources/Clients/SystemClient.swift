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
  public var quit: @Sendable () async -> Void
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
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = Relaunch.arguments(pid: ProcessInfo.processInfo.processIdentifier, bundlePath: Bundle.main.bundlePath)
        try? task.run()
        NSApp.terminate(nil)
      }
    },
    quit: {
      await MainActor.run { NSApp.terminate(nil) }
    }
  )

  public static let testValue = SystemClient()
}

/// The helper shell behind `relaunch`: it waits until this process exits, then opens the app again. It gives up after
/// `checks` looks 0.1 s apart, about 10 s, so a quit that was cancelled doesn't leave it waiting to reopen Vortex at the
/// next quit.
enum Relaunch {
  static let checks = 100

  /// Arguments for `/bin/sh`. The bundle path goes in as `$0`, never into the script, so no path can break it.
  static func arguments(pid: pid_t, bundlePath: String) -> [String] {
    let script = "n=0; while kill -0 \(pid) 2>/dev/null; do n=$((n+1)); [ $n -gt \(checks) ] && exit 0; sleep 0.1; done; "
      + "open \"$0\""
    return ["-c", script, bundlePath]
  }
}

extension DependencyValues {
  public var systemClient: SystemClient {
    get { self[SystemClient.self] }
    set { self[SystemClient.self] = newValue }
  }
}
