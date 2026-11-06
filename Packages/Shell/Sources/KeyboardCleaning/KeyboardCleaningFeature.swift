import ComposableArchitecture
import VortexCore
import VortexPlatform

/// Keyboard cleaning: every key on the Mac held back while the window shows the lock screen, until the user turns the
/// keyboard back on. Home's button starts it (`keyboardCleaning` in the environment). Meanwhile the shell keeps the
/// window open and Vortex in front, so a key that gets past the lock lands in Vortex and goes no further.
///
/// The lock screen draws the keyboard, and each key the user presses while wiping it looks a step cleaner.
@Reducer
struct KeyboardCleaningFeature {
  @ObservableState
  struct State: Equatable {
    var isLocked = false
    /// How often each key went down during this lock, by its place on the board. Only in memory, for the drawing, and
    /// gone when the lock ends; nothing stores, logs or sends it (a QA run's state shows the keys its commands press).
    var presses: [KeyboardKey: Int] = [:]
    /// The keyboard's layout as macOS said at the last lock: the lock screen draws ISO's board for ISO, ANSI's for the
    /// others.
    var layout: KeyboardLayout = .ansi
    /// What macOS says about Accessibility, as the shell last read it.
    @SharedReader(.permissionStatuses) var statuses

    /// How clean a key looks now: `KeyboardCleaningFeature.washes(after:)` its presses.
    func washes(of key: KeyboardKey) -> Int {
      KeyboardCleaningFeature.washes(after: presses[key] ?? 0)
    }
  }

  /// Three presses wash a key clean.
  static let cleanest = 3

  /// 0 dirty, as every key starts at each lock, to `cleanest`: each press washes a key one step, and more presses keep
  /// it there.
  static func washes(after presses: Int) -> Int {
    min(presses, cleanest)
  }

  enum Action: Equatable {
    case startTapped
    /// «Turn the keyboard back on».
    case stopTapped
    case lockFailed
    /// Accessibility went during the lock.
    case accessLost
    /// A key went down during the lock: the lock held it back, or it got past and reached Vortex's window.
    case keyPressed(KeyboardKey)
    case delegate(Delegate)

    enum Delegate: Equatable {
      /// Show Accessibility's page. `lockRefused`: macOS refused the tap while the status read granted.
      case openPage(lockRefused: Bool)
    }
  }

  @Dependency(\.keyboardLockClient) var keyboardLock
  @Dependency(\.windowClient) var window

  private enum CancelID {
    case lock
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .startTapped:
        guard !state.isLocked else { return .none }
        // Without Accessibility the click opens its page and locks nothing; it never asks macOS itself.
        guard state.statuses[.accessibility] != .notGranted else {
          return .send(.delegate(.openPage(lockRefused: false)))
        }
        state.isLocked = true
        state.layout = keyboardLock.layout()
        return .run { send in
          // Listening before the tap goes live, so no key pressed in between is lost; the unlock ends it.
          let presses = await keyboardLock.presses()
          await window.holdKeyboard(true)
          // The lock ended meanwhile, and its unlock may have run already: never lock after it.
          guard !Task.isCancelled else {
            await window.holdKeyboard(false)
            return
          }
          let isLocked = await keyboardLock.lock()
          guard !Task.isCancelled else {
            // The unlock may have come before this lock: let the keys go once more.
            if isLocked { await keyboardLock.unlock() }
            await window.holdKeyboard(false)
            return
          }
          guard isLocked else {
            await send(.lockFailed)
            return
          }
          for await key in presses {
            await send(.keyPressed(key))
          }
        }
        .cancellable(id: CancelID.lock, cancelInFlight: true)

      case let .keyPressed(key):
        guard state.isLocked else { return .none }
        state.presses[key, default: 0] += 1
        return .none

      case .stopTapped, .lockFailed, .accessLost:
        guard state.isLocked else { return .none }
        state.isLocked = false
        // Nothing of what was pressed outlives the lock: the next one starts with every key dirty.
        state.presses = [:]
        let isRefused = action == .lockFailed
        let readsGranted = state.statuses[.accessibility] == .granted
        return .merge(
          .cancel(id: CancelID.lock),
          .run { send in
            // On a loss the tap goes at once, and no page opens by itself.
            await keyboardLock.unlock()
            await window.holdKeyboard(false)
            // macOS refused the tap: Accessibility's page, which says to turn the switch off and on again when the
            // status reads granted.
            if isRefused { await send(.delegate(.openPage(lockRefused: readsGranted))) }
          }
        )

      case .delegate:
        return .none
      }
    }
  }
}
