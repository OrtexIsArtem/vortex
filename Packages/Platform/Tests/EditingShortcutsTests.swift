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

  @Test
  func capsLockChangesNothing() {
    #expect(EditingShortcuts.action(for: key("v", code: 9, [.command, .capsLock])) == #selector(NSText.paste(_:)))
  }

  /// Under a Cyrillic layout a key means what it types in the Latin layout the Mac uses for shortcuts: ⌘С is ⌘C on
  /// QWERTY, QWERTZ and AZERTY, whichever of them this Mac has.
  @Test
  func cyrillicLayoutMapsByTheLatinKey() throws {
    for (cyrillic, code) in [("м", UInt16(9)), ("с", 8), ("ф", 0), ("я", 6)] {
      let latin = try #require(EditingShortcuts.latinCharacter(keyCode: code))
      #expect(EditingShortcuts.action(for: key(cyrillic, code: code)) == EditingShortcuts.action(for: key(latin, code: code)))
    }
    #expect(EditingShortcuts.action(for: key("м", code: 9)) != nil)
  }
}
