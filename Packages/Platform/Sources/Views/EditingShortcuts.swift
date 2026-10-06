import AppKit
import Carbon.HIToolbox

/// Vortex has no main menu, so nothing maps the standard editing shortcuts; its panels send them themselves.
public enum EditingShortcuts {
  /// The action for ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z, ⇧⌘Z and ⌘Q; nil for any other key. Under a Cyrillic or other non-Latin
  /// layout the keys count as in the Latin one, as in every Mac app.
  public static func action(for event: NSEvent) -> Selector? {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let isShifted = flags == [.command, .shift]
    guard flags == .command || isShifted else { return nil }
    switch (latinKey(of: event), isShifted) {
    case ("x", false): return #selector(NSText.cut(_:))
    case ("c", false): return #selector(NSText.copy(_:))
    case ("v", false): return #selector(NSText.paste(_:))
    case ("a", false): return #selector(NSText.selectAll(_:))
    case ("z", false): return Selector(("undo:"))
    case ("z", true): return Selector(("redo:"))
    case ("q", false): return #selector(NSApplication.terminate(_:))
    default: return nil
    }
  }

  /// The key as a lowercased Latin character: as typed, or, when the layout types something else (⌘С in Russian), as
  /// the Latin layout the Mac uses for shortcuts (ABC, U.S.) types it.
  static func latinKey(of event: NSEvent) -> String? {
    if let typed = event.charactersIgnoringModifiers?.lowercased(), !typed.isEmpty, typed.unicodeScalars.allSatisfy(\.isASCII) {
      return typed
    }
    return latinCharacter(keyCode: event.keyCode)
  }

  private static func latinCharacter(keyCode: UInt16) -> String? {
    guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
          let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData),
          let bytes = CFDataGetBytePtr(Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue())
    else { return nil }
    var deadKeys: UInt32 = 0
    var length = 0
    var characters = [UniChar](repeating: 0, count: 4)
    let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
      UCKeyTranslate(
        layout,
        keyCode,
        UInt16(kUCKeyActionDisplay),
        0,
        UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &deadKeys,
        characters.count,
        &length,
        &characters
      )
    }
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: characters, count: length).lowercased()
  }
}
