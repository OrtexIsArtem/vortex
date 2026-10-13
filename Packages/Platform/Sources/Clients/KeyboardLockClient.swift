import AppKit
import ApplicationServices
import ComposableArchitecture

/// Holds back every key press on the Mac while the keyboard is cleaned: letters, modifiers, Esc, the function row and
/// the keys for brightness, sound and media. Mouse and trackpad keep working.
///
/// An active event tap does it, which macOS allows only with Accessibility (Input Monitoring only lets an app listen).
/// The Touch ID (power) button and Caps Lock act before any tap sees them. Keys that pass a tap anyway, as they do
/// while an app has secure input on, reach the window with the keyboard: the shell keeps Vortex's there meanwhile.
@DependencyClient
public struct KeyboardLockClient: Sendable {
  /// Whether Vortex has Accessibility. Asks nothing.
  public var hasAccess: @Sendable () -> Bool = { false }
  /// Shows the system's prompt the first time, which also puts Vortex in the Accessibility list, and opens
  /// System Settings › Privacy & Security › Accessibility.
  public var requestAccess: @Sendable () async -> Void
  /// Holds the keys back until `unlock`; false when macOS doesn't let Vortex do it. If Vortex quits or crashes, the
  /// keys come back with it.
  public var lock: @Sendable () async -> Bool = { false }
  public var unlock: @Sendable () async -> Void
}

extension KeyboardLockClient: DependencyKey {
  public static let liveValue = KeyboardLockClient(
    hasAccess: { AXIsProcessTrusted() },
    requestAccess: {
      await MainActor.run {
        // By name: `kAXTrustedCheckOptionPrompt` is a mutable global, which strict concurrency won't read.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
          NSWorkspace.shared.open(url)
        }
      }
    },
    lock: { await KeyboardTap.start() },
    unlock: { await KeyboardTap.stop() }
  )

  public static let testValue = KeyboardLockClient()
}

extension DependencyValues {
  public var keyboardLockClient: KeyboardLockClient {
    get { self[KeyboardLockClient.self] }
    set { self[KeyboardLockClient.self] = newValue }
  }
}

/// What the lock holds back.
enum KeyboardLockEvents {
  /// Keys down and up, modifiers, and the system-defined events, where the keys for brightness, sound and media come.
  static let mask: CGEventMask = [CGEventType.keyDown, .keyUp, .flagsChanged]
    .reduce(1 << CGEventMask(NX_SYSDEFINED)) { $0 | 1 << CGEventMask($1.rawValue) }
  /// System-defined events of keys: brightness, sound, media (aux control buttons), eject and menu. Those of the
  /// mouse's buttons, power and sleep pass.
  static let keySubtypes: Set<Int16> = [
    Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS), Int16(NX_SUBTYPE_EJECT_KEY), Int16(NX_SUBTYPE_MENU),
  ]

  static func isHeldBack(_ type: CGEventType, _ event: CGEvent) -> Bool {
    switch type {
    case .keyDown, .keyUp, .flagsChanged: true
    default: NSEvent(cgEvent: event).map { $0.type == .systemDefined && keySubtypes.contains($0.subtype.rawValue) } ?? false
    }
  }
}

/// The tap, on the main run loop: its callback only decides, and Vortex keeps heavy work off the main thread. Should
/// that ever keep keys waiting, macOS turns the tap off, and the callback turns it back on.
@MainActor
private enum KeyboardTap {
  static var tap: (port: CFMachPort, source: CFRunLoopSource)?

  static func start() -> Bool {
    guard tap == nil else { return true }
    // Without Accessibility macOS may make the tap and quietly leave the keys out of it.
    guard AXIsProcessTrusted(), let port = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: KeyboardLockEvents.mask,
      callback: { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
          MainActor.assumeIsolated { KeyboardTap.tap.map { CGEvent.tapEnable(tap: $0.port, enable: true) } }
          return Unmanaged.passUnretained(event)
        }
        return KeyboardLockEvents.isHeldBack(type, event) ? nil : Unmanaged.passUnretained(event)
      },
      userInfo: nil
    ) else { return false }
    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
      CFMachPortInvalidate(port)
      return false
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    tap = (port, source)
    return true
  }

  static func stop() {
    guard let (port, source) = tap else { return }
    CGEvent.tapEnable(tap: port, enable: false)
    CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    CFMachPortInvalidate(port)
    tap = nil
  }
}
