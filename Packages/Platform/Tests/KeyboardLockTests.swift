import AppKit
import Testing

@testable import VortexPlatform

/// What the keyboard lock holds back. Events here are only made, never posted, and no tap is installed.
struct KeyboardLockTests {
  @Test
  func keysAndModifiersAreHeldBackThePointerIsNeverAskedFor() throws {
    // The type decides for keys; an empty event stands in.
    let event = try #require(CGEvent(source: nil))
    for type in [CGEventType.keyDown, .keyUp, .flagsChanged] {
      #expect(KeyboardLockEvents.mask & (1 << CGEventMask(type.rawValue)) != 0)
      #expect(KeyboardLockEvents.isHeldBack(type, event))
    }
    for type in [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown, .mouseMoved, .scrollWheel] {
      #expect(KeyboardLockEvents.mask & (1 << CGEventMask(type.rawValue)) == 0)
    }
  }

  /// Brightness, sound and media (aux control buttons, subtype 8) are held back; the mouse's buttons (7) and power (1)
  /// pass.
  @Test(arguments: [(Int16(8), true), (7, false), (1, false)])
  func ofSystemDefinedEventsOnlyKeysAreHeldBack(subtype: Int16, isHeldBack: Bool) throws {
    let event = try #require(
      NSEvent.otherEvent(
        with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        subtype: subtype, data1: 0, data2: -1
      )?.cgEvent
    )
    #expect(KeyboardLockEvents.mask & (1 << CGEventMask(NX_SYSDEFINED)) != 0)
    #expect(KeyboardLockEvents.isHeldBack(CGEventType(rawValue: UInt32(NX_SYSDEFINED))!, event) == isHeldBack)
  }
}

/// Which key an event presses, for the cleaning screen's drawing: each key once, as it goes down.
struct KeyboardKeyDecodingTests {
  func key(_ code: UInt16, down: Bool = true, repeat isRepeat: Bool = false) throws -> CGEvent {
    let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down))
    event.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
    return event
  }

  func modifier(_ code: UInt16, flags: UInt64) throws -> CGEvent {
    let event = try key(code)
    event.type = .flagsChanged
    event.flags = CGEventFlags(rawValue: flags)
    return event
  }

  /// A brightness, sound or media key, as the top row sends it: key type, state (0xA down, 0xB up), repeat flag.
  func auxControl(_ keyType: Int32, down: Bool = true, repeat isRepeat: Bool = false) throws -> CGEvent {
    let data1 = Int(keyType) << 16 | (down ? 0x0A : 0x0B) << 8 | (isRepeat ? 1 : 0)
    return try #require(
      NSEvent.otherEvent(
        with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS), data1: data1, data2: -1
      )?.cgEvent
    )
  }

  static let shift = CGEventFlags.maskShift.rawValue
  static let leftShift = UInt64(NX_DEVICELSHIFTKEYMASK)
  static let rightShift = UInt64(NX_DEVICERSHIFTKEYMASK)

  @Test
  func aKeyCountsAsItGoesDownNeverOnReleaseOrWhileHeld() throws {
    #expect(KeyboardKey(pressedBy: try key(0x00)) == .a)
    #expect(KeyboardKey(pressedBy: try key(0x00, down: false)) == nil)
    #expect(KeyboardKey(pressedBy: try key(0x00, repeat: true)) == nil)
    #expect(KeyboardKey(pressedBy: try key(0x24)) == .return)
    #expect(KeyboardKey(pressedBy: try key(0x35)) == .escape)
    #expect(KeyboardKey(pressedBy: try key(0x0A)) == .section)
  }

  /// Every key of the board comes back as itself.
  @Test
  func everyKeyOfTheBoardIsItsOwnKeyCode() throws {
    let modifiers: Set<KeyboardKey> = [
      .leftShift, .rightShift, .control, .leftOption, .rightOption, .leftCommand, .rightCommand, .fn, .capsLock,
    ]
    for key in KeyboardKey.allCases where !modifiers.contains(key) {
      #expect(KeyboardKey(pressedBy: try self.key(key.rawValue)) == key)
    }
  }

  @Test
  func aModifierCountsWhenItGoesDownNeverWhenItGoesUp() throws {
    #expect(KeyboardKey(pressedBy: try modifier(0x38, flags: Self.shift | Self.leftShift)) == .leftShift)
    #expect(KeyboardKey(pressedBy: try modifier(0x38, flags: 0)) == nil)
    let command = CGEventFlags.maskCommand.rawValue
    #expect(KeyboardKey(pressedBy: try modifier(0x37, flags: command | UInt64(NX_DEVICELCMDKEYMASK))) == .leftCommand)
    #expect(KeyboardKey(pressedBy: try modifier(0x36, flags: command | UInt64(NX_DEVICERCMDKEYMASK))) == .rightCommand)
    let option = CGEventFlags.maskAlternate.rawValue
    #expect(KeyboardKey(pressedBy: try modifier(0x3D, flags: option | UInt64(NX_DEVICERALTKEYMASK))) == .rightOption)
    let control = CGEventFlags.maskControl.rawValue
    #expect(KeyboardKey(pressedBy: try modifier(0x3B, flags: control | UInt64(NX_DEVICELCTLKEYMASK))) == .control)
    #expect(KeyboardKey(pressedBy: try modifier(0x3F, flags: CGEventFlags.maskSecondaryFn.rawValue)) == .fn)
    #expect(KeyboardKey(pressedBy: try modifier(0x3F, flags: 0)) == nil)
  }

  /// With the left Shift held, the right one going up still reads up, and going down reads down.
  @Test
  func eachSideOfAModifierHasItsOwnBit() {
    let bothDown = CGEventFlags(rawValue: Self.shift | Self.leftShift | Self.rightShift)
    let leftOnly = CGEventFlags(rawValue: Self.shift | Self.leftShift)
    #expect(KeyboardKey.pressed(.flagsChanged, keyCode: 0x3C, isRepeat: false, flags: bothDown) == .rightShift)
    #expect(KeyboardKey.pressed(.flagsChanged, keyCode: 0x3C, isRepeat: false, flags: leftOnly) == nil)
    // An event without the side bits, as an app may post, goes by the shared flag.
    #expect(KeyboardKey.pressed(.flagsChanged, keyCode: 0x3C, isRepeat: false, flags: .maskShift) == .rightShift)
  }

  /// Caps Lock sends one event a press, turning on or off: each one counts.
  @Test
  func capsLockCountsEachTimeItTurns() throws {
    #expect(KeyboardKey(pressedBy: try modifier(0x39, flags: CGEventFlags.maskAlphaShift.rawValue)) == .capsLock)
    #expect(KeyboardKey(pressedBy: try modifier(0x39, flags: 0)) == .capsLock)
  }

  @Test(arguments: [
    (NX_KEYTYPE_BRIGHTNESS_DOWN, KeyboardKey.f1),
    (NX_KEYTYPE_BRIGHTNESS_UP, .f2),
    (NX_KEYTYPE_ILLUMINATION_DOWN, .f5),
    (NX_KEYTYPE_ILLUMINATION_UP, .f6),
    (NX_KEYTYPE_REWIND, .f7),
    (NX_KEYTYPE_PREVIOUS, .f7),
    (NX_KEYTYPE_PLAY, .f8),
    (NX_KEYTYPE_FAST, .f9),
    (NX_KEYTYPE_NEXT, .f9),
    (NX_KEYTYPE_MUTE, .f10),
    (NX_KEYTYPE_SOUND_DOWN, .f11),
    (NX_KEYTYPE_SOUND_UP, .f12),
  ])
  func theTopRowsSystemKeysWashTheirFKey(keyType: Int32, key: KeyboardKey) throws {
    #expect(KeyboardKey(pressedBy: try auxControl(keyType)) == key)
    #expect(KeyboardKey(pressedBy: try auxControl(keyType, down: false)) == nil)
    #expect(KeyboardKey(pressedBy: try auxControl(keyType, repeat: true)) == nil)
  }

  /// Mission Control, Spotlight or Launchpad, Dictation and Do Not Disturb come as key codes of their own; the real
  /// F keys (with fn, or as standard function keys) come as theirs.
  @Test(arguments: [
    (UInt16(0xA0), KeyboardKey.f3), (0x83, .f4), (0xB1, .f4), (0xB0, .f5), (0xB2, .f6),
    (0x4A, .f10), (0x49, .f11), (0x48, .f12),
    (0x7A, .f1), (0x63, .f3), (0x6F, .f12),
  ])
  func theTopRowsOwnKeyCodesWashTheirFKey(code: UInt16, key: KeyboardKey) throws {
    #expect(KeyboardKey(pressedBy: try self.key(code)) == key)
    #expect(KeyboardKey(pressedBy: try self.key(code, down: false)) == nil)
    #expect(KeyboardKey(pressedBy: try self.key(code, repeat: true)) == nil)
  }

  /// With fn held, the arrows send Home, End, Page Up and Page Down, delete sends Forward Delete and return Enter.
  @Test
  func whatKeysSendWithFnWashThoseKeys() throws {
    #expect(KeyboardKey(pressedBy: try key(0x73)) == .leftArrow)
    #expect(KeyboardKey(pressedBy: try key(0x77)) == .rightArrow)
    #expect(KeyboardKey(pressedBy: try key(0x74)) == .upArrow)
    #expect(KeyboardKey(pressedBy: try key(0x79)) == .downArrow)
    #expect(KeyboardKey(pressedBy: try key(0x75)) == .delete)
    #expect(KeyboardKey(pressedBy: try key(0x4C)) == .return)
  }

  /// The numpad, F13 and up, right Control, eject and the mouse's buttons have no place on the board.
  @Test
  func keysWithNoPlaceOnTheBoardAreLeftOut() throws {
    #expect(KeyboardKey(pressedBy: try key(0x52)) == nil) // keypad 0
    #expect(KeyboardKey(pressedBy: try key(0x69)) == nil) // F13
    #expect(KeyboardKey(pressedBy: try key(0x5D)) == nil) // JIS ¥
    let control = CGEventFlags.maskControl.rawValue | UInt64(NX_DEVICERCTLKEYMASK)
    #expect(KeyboardKey(pressedBy: try modifier(0x3E, flags: control)) == nil)
    #expect(KeyboardKey(pressedBy: try auxControl(NX_KEYTYPE_EJECT)) == nil)
    let mouse = try #require(
      NSEvent.otherEvent(
        with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        subtype: 7, data1: Int(NX_KEYTYPE_SOUND_UP) << 16 | 0x0A << 8, data2: -1
      )?.cgEvent
    )
    #expect(KeyboardKey(pressedBy: mouse) == nil)
    #expect(KeyboardKey(pressedBy: try #require(CGEvent(source: nil))) == nil)
  }

  @Test
  func theLayoutIsWhatHIToolboxSays() {
    #expect(KeyboardLayout(physicalType: 0x414E_5349) == .ansi) // 'ANSI'
    #expect(KeyboardLayout(physicalType: 0x4953_4F20) == .iso) // 'ISO '
    #expect(KeyboardLayout(physicalType: 0x4A49_5320) == .jis) // 'JIS '
    #expect(KeyboardLayout(physicalType: 0x3F3F_3F3F) == .ansi) // '????'
  }
}
