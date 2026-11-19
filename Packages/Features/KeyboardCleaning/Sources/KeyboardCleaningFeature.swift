import ComposableArchitecture
import VortexCore
import VortexPlatform

extension Hotkey {
  /// Locks the keyboard for cleaning. None by default; the user records it on the utility's page in Settings ›
  /// Features, where the shell shows it, and the shell listens for it through the utility action.
  static let lockKeyboard = Hotkey("lockKeyboard")
}

/// Keyboard cleaning: every key on the Mac held back while the window shows the lock screen, until the user turns the
/// keyboard back on. Its utility action starts it, with the window open; the lock screen is its cover over the window
/// (`WindowCover`), which keeps the window open and Vortex in front meanwhile, so a key that gets past the lock lands
/// in Vortex and goes no further.
///
/// The lock screen draws the keyboard, and each key the user presses while wiping it looks a step cleaner.
@Reducer
struct KeyboardCleaningFeature: Sendable {
  static let id: FeatureID = "keyboard"

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
    /// The cover over the window: the lock screen while the keys are locked. Only this feature writes its own.
    @Shared(.windowCover) var cover

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
    /// The utility action, from the dock or its shortcut, run by the shell with the window open.
    case startTapped
    /// «Turn the keyboard back on».
    case stopTapped
    case lockFailed
    /// Accessibility went during the lock.
    case accessLost
    /// A key went down during the lock: the lock held it back, or it got past and reached Vortex's window.
    case keyPressed(KeyboardKey)
    /// The utility stops, as Remove stops it: a lock under way ends.
    case stopped
    /// Its settings page showed: the statuses are read again.
    case settingsShown
    /// "Turn on" in its settings: the shell's page.
    case turnOnTapped(Permission)
    /// "Restart Vortex" in its settings, once macOS granted Accessibility to the next launch.
    case restartTapped
  }

  @Dependency(\.keyboardLockClient) var keyboardLock
  @Dependency(\.permissionPage) var permissionPage
  @Dependency(\.permissionsClient) var permissions
  @Dependency(\.systemClient) var system

  private enum CancelID {
    case lock
    case access
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .startTapped:
        guard !state.isLocked else { return .none }
        // Without Accessibility the click opens its page and locks nothing; it never asks macOS itself.
        guard state.statuses[.accessibility] != .notGranted else {
          return .run { _ in await permissionPage.open(.accessibility) }
        }
        state.isLocked = true
        state.layout = keyboardLock.layout()
        // The lock screen covers the window, and Vortex holds the keyboard meanwhile.
        state.$cover.withLock { $0 = WindowCover(feature: Self.id, holdsKeyboard: true) }
        return .merge(
          .run { send in
            // Listening before the tap goes live, so no key pressed in between is lost; the unlock ends it.
            let presses = await keyboardLock.presses()
            // The lock ended meanwhile, and its unlock may have run already: never lock after it.
            guard !Task.isCancelled else { return }
            let isLocked = await keyboardLock.lock()
            guard !Task.isCancelled else {
              // The unlock may have come before this lock: let the keys go once more.
              if isLocked { await keyboardLock.unlock() }
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
          .cancellable(id: CancelID.lock, cancelInFlight: true),
          // Losing Accessibility ends the lock at once; no page opens by itself.
          .run { [statuses = state.$statuses] send in
            for await statuses in statuses.publisher.values where statuses[.accessibility] == .notGranted {
              await send(.accessLost)
              return
            }
          }
          .cancellable(id: CancelID.access, cancelInFlight: true)
        )

      case let .keyPressed(key):
        guard state.isLocked else { return .none }
        state.presses[key, default: 0] += 1
        return .none

      case .stopTapped, .lockFailed, .accessLost, .stopped:
        guard state.isLocked else { return .none }
        state.isLocked = false
        // Nothing of what was pressed outlives the lock: the next one starts with every key dirty.
        state.presses = [:]
        // The cover goes, and the window with it: the keys go back to the app the user was in.
        state.$cover.withLock { $0 = nil }
        let isRefused = action == .lockFailed
        let readsGranted = state.statuses[.accessibility] == .granted
        return .merge(
          .cancel(id: CancelID.lock),
          .cancel(id: CancelID.access),
          .run { _ in
            // On a loss the tap goes at once, and no page opens by itself.
            await keyboardLock.unlock()
            // macOS refused the tap: Accessibility's page, which says to turn the switch off and on again when the
            // status reads granted.
            guard isRefused else { return }
            if readsGranted {
              await permissionPage.openRefused(.accessibility)
            } else {
              await permissionPage.open(.accessibility)
            }
          }
        )

      case .settingsShown:
        return .run { _ in await permissions.refresh() }

      case let .turnOnTapped(permission):
        return .run { _ in await permissionPage.open(permission) }

      case .restartTapped:
        return .run { _ in await system.relaunch() }
      }
    }
  }
}
