import AppKit
import Testing

@testable import VortexPlatform

@MainActor
struct EditingShortcutsTests {
  func key(_ characters: String, code: UInt16, _ flags: NSEvent.ModifierFlags = .command) -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: flags,
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: characters,
      isARepeat: false,
      keyCode: code
    )!
  }

  @Test
  func latinLayoutMapsByTheTypedLetter() {
    #expect(EditingShortcuts.action(for: key("v", code: 9)) == #selector(NSText.paste(_:)))
    #expect(EditingShortcuts.action(for: key("a", code: 0)) == #selector(NSText.selectAll(_:)))
    #expect(EditingShortcuts.action(for: key("z", code: 6, [.command, .shift])) == Selector(("redo:")))
    #expect(EditingShortcuts.action(for: key("v", code: 9, [.command, .option])) == nil)
    #expect(EditingShortcuts.action(for: key("v", code: 9, [])) == nil)
  }

  /// C and V sit on the same keys in QWERTY, QWERTZ and AZERTY, the Latin layouts shortcuts fall back to.
  @Test
  func cyrillicLayoutMapsByTheLatinKey() {
    #expect(EditingShortcuts.action(for: key("м", code: 9)) == #selector(NSText.paste(_:)))
    #expect(EditingShortcuts.action(for: key("с", code: 8)) == #selector(NSText.copy(_:)))
  }
}
