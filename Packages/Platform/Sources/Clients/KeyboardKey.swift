import AppKit

/// A key of the Mac's keyboard by its place, as keyboard cleaning draws it: a MacBook's keys, ANSI and ISO. The raw
/// value is the virtual key code (`kVK_…`) the place sends with "Use F1, F2, etc. keys as standard function keys" on,
/// so the brightness-down key is `f1`. Keys with no place there have no case and wash nothing: the numpad, F13 and up,
/// right Control and other keyboards' own keys. Only Enter goes to `return`, as fn+Return on a MacBook sends it too.
public enum KeyboardKey: UInt16, CaseIterable, Sendable {
  case a = 0x00, s = 0x01, d = 0x02, f = 0x03, h = 0x04, g = 0x05, z = 0x06, x = 0x07, c = 0x08, v = 0x09
  /// § left of 1 on an ISO keyboard, where an ANSI one has `grave`.
  case section = 0x0A
  case b = 0x0B, q = 0x0C, w = 0x0D, e = 0x0E, r = 0x0F, y = 0x10, t = 0x11
  case digit1 = 0x12, digit2 = 0x13, digit3 = 0x14, digit4 = 0x15, digit6 = 0x16, digit5 = 0x17, equal = 0x18
  case digit9 = 0x19, digit7 = 0x1A, minus = 0x1B, digit8 = 0x1C, digit0 = 0x1D, rightBracket = 0x1E, o = 0x1F
  case u = 0x20, leftBracket = 0x21, i = 0x22, p = 0x23, `return` = 0x24, l = 0x25, j = 0x26, quote = 0x27, k = 0x28
  case semicolon = 0x29, backslash = 0x2A, comma = 0x2B, slash = 0x2C, n = 0x2D, m = 0x2E, period = 0x2F, tab = 0x30
  case space = 0x31
  /// ` left of 1 on an ANSI keyboard, left of Z on an ISO one.
  case grave = 0x32
  case delete = 0x33, escape = 0x35
  case rightCommand = 0x36, leftCommand = 0x37, leftShift = 0x38, capsLock = 0x39, leftOption = 0x3A, control = 0x3B
  case rightShift = 0x3C, rightOption = 0x3D, fn = 0x3F
  case f1 = 0x7A, f2 = 0x78, f3 = 0x63, f4 = 0x76, f5 = 0x60, f6 = 0x61, f7 = 0x62, f8 = 0x64, f9 = 0x65, f10 = 0x6D
  case f11 = 0x67, f12 = 0x6F
  case leftArrow = 0x7B, rightArrow = 0x7C, downArrow = 0x7D, upArrow = 0x7E
}

// MARK: - Decoding

extension KeyboardKey {
  /// The key `event` presses: nil for a release, for a repeat while the key is held, and for a key with no place on the
  /// board. Reads only which key it is, never what it types. Light enough for an event tap's callback.
  public init?(pressedBy event: CGEvent) {
    let type = event.type
    let key: KeyboardKey? = switch type {
    case .keyDown, .keyUp, .flagsChanged:
      Self.pressed(
        type,
        keyCode: event.getIntegerValueField(.keyboardEventKeycode),
        isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
        flags: event.flags
      )
    case _ where type.rawValue == UInt32(NX_SYSDEFINED):
      NSEvent(cgEvent: event).flatMap { event in
        let isAuxControl = event.subtype.rawValue == Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS)
        return isAuxControl ? Self.pressed(auxControlData: event.data1) : nil
      }
    default:
      nil
    }
    guard let key else { return nil }
    self = key
  }

  /// A key event's fields → the key it presses. A key counts as it goes down: `keyDown` but not its repeats, and a
  /// modifier's `flagsChanged` that turns it on.
  static func pressed(_ type: CGEventType, keyCode: Int64, isRepeat: Bool, flags: CGEventFlags) -> KeyboardKey? {
    guard let code = UInt16(exactly: keyCode) else { return nil }
    switch type {
    case .keyDown:
      return isRepeat ? nil : sentBy[code] ?? KeyboardKey(rawValue: code)
    case .flagsChanged:
      guard let key = KeyboardKey(rawValue: code), key.isDown(in: flags) == true else { return nil }
      return key
    default:
      return nil
    }
  }

  /// Key codes a MacBook's keys send besides their own, at the place of the key that sends them: the top row's
  /// Mission Control, Spotlight, Launchpad, Dictation and Do Not Disturb, the sound keys of keyboards that send them as
  /// keys, and what the arrows, delete and return send with fn held. A numpad's Enter sends what fn+Return does, so it
  /// washes return too.
  static let sentBy: [UInt16: KeyboardKey] = [
    0xA0: .f3, // Mission Control
    0x82: .f4, // Dashboard, on older keyboards
    0x83: .f4, // Launchpad
    0xB1: .f4, // Spotlight
    0xB0: .f5, // Dictation
    0xB2: .f6, // Do Not Disturb
    0x4A: .f10, // kVK_Mute
    0x49: .f11, // kVK_VolumeDown
    0x48: .f12, // kVK_VolumeUp
    0x73: .leftArrow, // Home
    0x77: .rightArrow, // End
    0x74: .upArrow, // Page Up
    0x79: .downArrow, // Page Down
    0x75: .delete, // Forward Delete
    0x4C: .return, // Enter: fn+Return on a MacBook, or a numpad's
  ]

  /// An aux control button event (`NX_SUBTYPE_AUX_CONTROL_BUTTONS`), as the top row sends brightness, keyboard
  /// backlight, media and sound: `data1` holds the key type in bits 16–31, the state in bits 8–15 (0xA down, 0xB up)
  /// and the repeat flag in bit 0. Each goes to the F key whose place sends it.
  static func pressed(auxControlData data1: Int) -> KeyboardKey? {
    let keyType = Int32((data1 >> 16) & 0xFFFF)
    guard (data1 >> 8) & 0xFF == 0x0A, data1 & 0x1 == 0 else { return nil }
    return auxControlKeys[keyType]
  }

  static let auxControlKeys: [Int32: KeyboardKey] = [
    NX_KEYTYPE_BRIGHTNESS_DOWN: .f1,
    NX_KEYTYPE_BRIGHTNESS_UP: .f2,
    NX_KEYTYPE_ILLUMINATION_DOWN: .f5,
    NX_KEYTYPE_ILLUMINATION_UP: .f6,
    NX_KEYTYPE_REWIND: .f7,
    NX_KEYTYPE_PREVIOUS: .f7,
    NX_KEYTYPE_PLAY: .f8,
    NX_KEYTYPE_FAST: .f9,
    NX_KEYTYPE_NEXT: .f9,
    NX_KEYTYPE_MUTE: .f10,
    NX_KEYTYPE_SOUND_DOWN: .f11,
    NX_KEYTYPE_SOUND_UP: .f12,
  ]

  /// Whether this modifier is down after its `flagsChanged` event; nil for a key that isn't one. Each side of Shift,
  /// Option and Command has a bit of its own, so a right Shift let go while the left one is held reads up; an event
  /// without those bits, as an app may post, goes by the shared flag. Caps Lock sends one event a press, whichever way
  /// it turns, so each one counts.
  func isDown(in flags: CGEventFlags) -> Bool? {
    func side(_ own: Int32, _ other: Int32, _ shared: CGEventFlags) -> Bool {
      let bits = flags.rawValue & UInt64(own | other)
      return bits == 0 ? flags.contains(shared) : bits & UInt64(own) != 0
    }
    return switch self {
    case .leftShift: side(NX_DEVICELSHIFTKEYMASK, NX_DEVICERSHIFTKEYMASK, .maskShift)
    case .rightShift: side(NX_DEVICERSHIFTKEYMASK, NX_DEVICELSHIFTKEYMASK, .maskShift)
    case .control: side(NX_DEVICELCTLKEYMASK, NX_DEVICERCTLKEYMASK, .maskControl)
    case .leftOption: side(NX_DEVICELALTKEYMASK, NX_DEVICERALTKEYMASK, .maskAlternate)
    case .rightOption: side(NX_DEVICERALTKEYMASK, NX_DEVICELALTKEYMASK, .maskAlternate)
    case .leftCommand: side(NX_DEVICELCMDKEYMASK, NX_DEVICERCMDKEYMASK, .maskCommand)
    case .rightCommand: side(NX_DEVICERCMDKEYMASK, NX_DEVICELCMDKEYMASK, .maskCommand)
    case .fn: flags.contains(.maskSecondaryFn)
    case .capsLock: true
    default: nil
    }
  }
}

// MARK: - Layout

/// The physical layout of a keyboard, as macOS tells it: ANSI (US), ISO (most of Europe: § top left, a key left of Z,
/// a tall Return) or JIS (Japan).
public enum KeyboardLayout: String, CaseIterable, Sendable {
  case ansi, iso, jis

  /// HIToolbox's answer for a keyboard type (`PhysicalKeyboardLayoutType`, a four-character code); ANSI when it
  /// doesn't know.
  init(physicalType: UInt32) {
    self = switch physicalType {
    case 0x4953_4F20: .iso // 'ISO '
    case 0x4A49_5320: .jis // 'JIS '
    default: .ansi // 'ANSI', or '????'
    }
  }
}
