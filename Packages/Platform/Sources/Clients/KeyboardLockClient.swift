import AppKit
import ApplicationServices
import Carbon
import ComposableArchitecture

/// Holds back every key press on the Mac while the keyboard is cleaned: letters, modifiers, Esc, the function row and
/// the keys for brightness, sound and media. Mouse and trackpad keep working.
///
/// An active event tap does it, which macOS allows only with Accessibility (Input Monitoring only lets an app listen).
/// The Touch ID (power) button acts before any tap sees it, and Caps Lock turns on or off before a tap can hold it
/// back. Keys that pass a tap anyway, as they do while an app has secure input on, reach the window with the keyboard:
/// the shell keeps Vortex's there meanwhile.
///
/// Privacy: only while the lock is on, the keys it holds back come out of `presses` as places on the keyboard
/// (`KeyboardKey`), for the cleaning screen to draw them washed. Never what they type; the screen keeps how often each
/// place went down, in memory, until the lock ends. Vortex never stores, logs or sends them.
@DependencyClient
public struct KeyboardLockClient: Sendable {
  /// Holds the keys back until `unlock`; false when macOS doesn't let Vortex do it. If Vortex quits or crashes, the
  /// keys come back with it.
  public var lock: @Sendable () async -> Bool = { false }
  public var unlock: @Sendable () async -> Void
  /// The keys the lock holds back, each once as it goes down: never on release, and a key held down counts once. Keys
  /// with no place on the drawn keyboard are left out. It ends with `unlock`.
  public var presses: @Sendable () async -> AsyncStream<KeyboardKey> = { .finished }
  /// The physical layout of the keyboard used last, as macOS knows it. Read on the main thread.
  public var layout: @Sendable () -> KeyboardLayout = { .ansi }
}

extension KeyboardLockClient: DependencyKey {
  public static let liveValue = KeyboardLockClient(
    lock: { await KeyboardTap.start() },
    unlock: { await KeyboardTap.stop() },
    presses: { await KeyboardTap.presses() },
    layout: { KeyboardLayout.current }
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

/// The tap, on the main run loop: its callback only decides and hands a pressed key on, and Vortex keeps heavy work
/// off the main thread. Should that ever keep keys waiting, macOS turns the tap off, and the callback turns it back on.
@MainActor
private enum KeyboardTap {
  static var tap: (port: CFMachPort, source: CFRunLoopSource)?
  /// Who gets the pressed keys: the cleaning screen, while the lock is on.
  static var listeners: [UUID: AsyncStream<KeyboardKey>.Continuation] = [:]

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
        guard KeyboardLockEvents.isHeldBack(type, event) else { return Unmanaged.passUnretained(event) }
        if let key = KeyboardKey(pressedBy: event) {
          MainActor.assumeIsolated { KeyboardTap.listeners.values.forEach { $0.yield(key) } }
        }
        return nil
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
    listeners.values.forEach { $0.finish() }
    listeners = [:]
    guard let (port, source) = tap else { return }
    CGEvent.tapEnable(tap: port, enable: false)
    CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    CFMachPortInvalidate(port)
    tap = nil
  }

  static func presses() -> AsyncStream<KeyboardKey> {
    let (stream, continuation) = AsyncStream.makeStream(of: KeyboardKey.self, bufferingPolicy: .bufferingNewest(64))
    let id = UUID()
    listeners[id] = continuation
    continuation.onTermination = { _ in Task { @MainActor in KeyboardTap.listeners[id] = nil } }
    return stream
  }
}

extension KeyboardLayout {
  /// The keyboard used last: `KBGetLayoutType(LMGetKbdType())`. HIToolbox still has KBGetLayoutType, but the SDK no
  /// longer declares it, so it is looked up once at runtime; without it, ANSI.
  static var current: KeyboardLayout {
    getLayoutType.map { KeyboardLayout(physicalType: $0(Int16(LMGetKbdType()))) } ?? .ansi
  }

  private typealias GetLayoutType = @convention(c) (Int16) -> UInt32

  private static let getLayoutType: GetLayoutType? = {
    let path = "/System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework/HIToolbox"
    guard let toolbox = dlopen(path, RTLD_LAZY), let symbol = dlsym(toolbox, "KBGetLayoutType") else { return nil }
    return unsafeBitCast(symbol, to: GetLayoutType.self)
  }()
}
