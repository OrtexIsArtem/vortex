import ComposableArchitecture
import VortexCore
import VortexPlatform

/// Keyboard cleaning: every key on the Mac held back while the window shows the lock screen, until the user turns the
/// keyboard back on. Home's button starts it (`keyboardCleaning` in the environment). Meanwhile the shell keeps the
/// window open and Vortex in front, so a key that gets past the lock lands in Vortex and goes no further.
@Reducer
struct KeyboardCleaningFeature {
  @ObservableState
  struct State: Equatable {
    var isLocked = false
    /// What macOS says about Accessibility, as the shell last read it.
    @SharedReader(.permissionStatuses) var statuses
  }

  enum Action: Equatable {
    case startTapped
    /// «Увімкнути клавіатуру».
    case stopTapped
    case lockFailed
    /// Accessibility went during the lock.
    case accessLost
    case delegate(Delegate)

    enum Delegate: Equatable {
      /// Show Accessibility's page. `lockRefused`: macOS refused the tap while the status read granted.
      case openPage(lockRefused: Bool)
    }
  }

  @Dependency(\.keyboardLockClient) var keyboardLock
  @Dependency(\.windowClient) var window

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
        return .run { send in
          await window.holdKeyboard(true)
          if await !keyboardLock.lock() { await send(.lockFailed) }
        }

      case .stopTapped, .lockFailed, .accessLost:
        guard state.isLocked else { return .none }
        state.isLocked = false
        let isRefused = action == .lockFailed
        let readsGranted = state.statuses[.accessibility] == .granted
        return .run { send in
          // On a loss the tap goes at once, and no page opens by itself.
          await keyboardLock.unlock()
          await window.holdKeyboard(false)
          // macOS refused the tap: Accessibility's page, which says to turn the switch off and on again when the
          // status reads granted.
          if isRefused { await send(.delegate(.openPage(lockRefused: readsGranted))) }
        }

      case .delegate:
        return .none
      }
    }
  }
}
