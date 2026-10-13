import ComposableArchitecture
import VortexPlatform

/// Keyboard cleaning: every key on the Mac held back while the window shows the lock screen, until the user turns the
/// keyboard back on. Home's button starts it (`keyboardCleaning` in the environment). Meanwhile the shell keeps the
/// window open and Vortex in front, so a key that gets past the lock lands in Vortex and goes no further.
@Reducer
struct KeyboardCleaningFeature {
  @ObservableState
  struct State: Equatable {
    var isLocked = false
  }

  enum Action: Equatable {
    case startTapped
    /// «Увімкнути клавіатуру».
    case stopTapped
    case lockFailed
  }

  @Dependency(\.keyboardLockClient) var keyboardLock
  @Dependency(\.windowClient) var window

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .startTapped:
        guard !state.isLocked else { return .none }
        // Without Accessibility the click asks for it: the system's prompt the first time, then System Settings.
        guard keyboardLock.hasAccess() else {
          return .run { _ in await keyboardLock.requestAccess() }
        }
        state.isLocked = true
        return .run { send in
          await window.holdKeyboard(true)
          if await !keyboardLock.lock() { await send(.lockFailed) }
        }

      case .stopTapped, .lockFailed:
        guard state.isLocked else { return .none }
        state.isLocked = false
        let isRefused = action == .lockFailed
        return .run { _ in
          await keyboardLock.unlock()
          await window.holdKeyboard(false)
          // macOS refused the tap though Vortex looked allowed: its switch in System Settings may need turning back on.
          if isRefused { await keyboardLock.requestAccess() }
        }
      }
    }
  }
}
