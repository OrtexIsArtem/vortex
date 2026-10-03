import ComposableArchitecture
import KeyboardShortcuts
import SwiftUI

/// Global keyboard shortcuts of the app. The user picks the keys in settings; none is set by default.
public enum Hotkey: String, CaseIterable, Sendable {
  case openVortex
}

extension Hotkey {
  var name: KeyboardShortcuts.Name {
    switch self {
    case .openVortex: .openVortex
    }
  }
}

extension KeyboardShortcuts.Name {
  static let openVortex = Self("openVortex")
}

/// Presses of the global shortcuts.
@DependencyClient
public struct HotkeyClient: Sendable {
  public var presses: @Sendable () async -> AsyncStream<Hotkey> = { .finished }
}

extension HotkeyClient: DependencyKey {
  public static let liveValue = HotkeyClient(
    presses: {
      await MainActor.run {
        let (stream, continuation) = AsyncStream.makeStream(of: Hotkey.self)
        for hotkey in Hotkey.allCases {
          KeyboardShortcuts.onKeyUp(for: hotkey.name) {
            continuation.yield(hotkey)
          }
        }
        return stream
      }
    }
  )

  public static let testValue = HotkeyClient()
}

extension DependencyValues {
  public var hotkeyClient: HotkeyClient {
    get { self[HotkeyClient.self] }
    set { self[HotkeyClient.self] = newValue }
  }
}

/// Field where the user records the keys for a shortcut. Stored by KeyboardShortcuts in UserDefaults.
public struct HotkeyRecorder: View {
  private let hotkey: Hotkey

  public init(_ hotkey: Hotkey) {
    self.hotkey = hotkey
  }

  public var body: some View {
    KeyboardShortcuts.Recorder(for: hotkey.name)
  }
}
