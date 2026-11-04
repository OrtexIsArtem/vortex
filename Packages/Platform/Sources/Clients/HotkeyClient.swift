import AppKit
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
    RecorderField(name: hotkey.shortcutName)
      .frame(width: Self.width)
      .accessibilityLabel(label)
  }

  /// The library's field is 130 pt whatever its words, and the Ukrainian placeholders App/KeyboardShortcuts gives it
  /// need more: as wide as the longer of "Record Shortcut" and "Press Shortcut" in the app's language, never narrower
  /// than the library's own.
  static let width: CGFloat = {
    let bundle = [Bundle.main.resourceURL, Bundle.main.bundleURL]
      .compactMap { $0?.appending(path: "KeyboardShortcuts_KeyboardShortcuts.bundle") }
      .lazy.compactMap { Bundle(url: $0) }.first
    guard let bundle else { return 130 }
    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let widest = ["record_shortcut", "press_shortcut"]
      .map { (bundle.localizedString(forKey: $0, value: nil, table: nil) as NSString).size(withAttributes: [.font: font]).width }
      .max() ?? 0
    // The text gets the field less 29 pt: the left inset and the clear button.
    return max(130, (widest + 29 + 2).rounded(.up))
  }()
}

/// The library's recorder, made as its SwiftUI `Recorder(for:)` makes it, but free to take the width it is given: the
/// library holds its field at 130 pt.
private struct RecorderField: NSViewRepresentable {
  let name: KeyboardShortcuts.Name

  func makeNSView(context: Context) -> KeyboardShortcuts.RecorderCocoa {
    let recorder = KeyboardShortcuts.RecorderCocoa(for: name)
    recorder.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return recorder
  }

  func updateNSView(_ recorder: KeyboardShortcuts.RecorderCocoa, context: Context) {
    if recorder.shortcutName != name { recorder.shortcutName = name }
  }
}
