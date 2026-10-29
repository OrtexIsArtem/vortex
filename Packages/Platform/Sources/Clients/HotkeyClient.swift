import ComposableArchitecture
import KeyboardShortcuts
import SwiftUI

/// A global keyboard shortcut. The user records the keys in settings; none is set by default.
/// Each module declares its own: `extension Hotkey { static let openClipboard = Hotkey("openClipboard") }`.
public struct Hotkey: Hashable, Sendable {
  /// Stable name; KeyboardShortcuts stores the keys under it. Must not contain a dot.
  public let name: String

  public init(_ name: String) {
    self.name = name
  }

  var shortcutName: KeyboardShortcuts.Name {
    KeyboardShortcuts.Name(name)
  }
}

/// Presses of global shortcuts.
@DependencyClient
public struct HotkeyClient: Sendable {
  /// Every press of the shortcut. Ending the stream stops listening.
  public var presses: @Sendable (_ hotkey: Hotkey) -> AsyncStream<Void> = { _ in .finished }
  /// The keys the user recorded for the shortcut, as the menus show them ("⌥⌘V"); nil while none is set.
  public var shortcut: @Sendable (_ hotkey: Hotkey) async -> String? = { _ in nil }
}

extension HotkeyClient: DependencyKey {
  public static let liveValue = HotkeyClient(
    presses: { hotkey in
      AsyncStream { continuation in
        let listener = Task { @MainActor in
          // On the press, not the release, so nothing waits for the keys to come up; a held key doesn't repeat.
          for await _ in KeyboardShortcuts.events(.keyDown, for: hotkey.shortcutName) {
            continuation.yield()
          }
          continuation.finish()
        }
        continuation.onTermination = { _ in listener.cancel() }
      }
    },
    shortcut: { hotkey in
      await MainActor.run { KeyboardShortcuts.getShortcut(for: hotkey.shortcutName)?.description }
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

/// Field where the user records the keys for a shortcut.
public struct HotkeyRecorder: View {
  private let hotkey: Hotkey
  private let label: Text

  /// `label` names the shortcut for VoiceOver; the row around the field shows it on screen.
  public init(_ hotkey: Hotkey, label: Text) {
    self.hotkey = hotkey
    self.label = label
  }

  public var body: some View {
    KeyboardShortcuts.Recorder(for: hotkey.shortcutName)
      .accessibilityLabel(label)
  }
}
