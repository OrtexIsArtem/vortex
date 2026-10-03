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
        // A helper shell waits until this process exits, then opens the app again.
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open \"$0\"", Bundle.main.bundlePath]
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

extension DependencyValues {
  public var systemClient: SystemClient {
    get { self[SystemClient.self] }
    set { self[SystemClient.self] = newValue }
  }
}
