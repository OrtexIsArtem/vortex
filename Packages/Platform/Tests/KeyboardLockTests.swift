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
