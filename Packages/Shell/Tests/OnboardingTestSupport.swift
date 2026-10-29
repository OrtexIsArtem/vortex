import ComposableArchitecture
import Foundation
import VortexCore
import VortexPlatform

@testable import VortexShell

extension OnboardingProgress {
  /// An onboarding the user finished.
  static var finished: OnboardingProgress {
    var progress = OnboardingProgress()
    progress.completed = true
    progress.page = OnboardingPage.done.id
    return progress
  }

  static func at(_ page: OnboardingPage) -> OnboardingProgress {
    var progress = OnboardingProgress()
    progress.page = page.id
    return progress
  }
}

/// Features as they declare their needs; ids as in the app. "secrets" also brings a step in some tests.
enum OnboardingNeeds {
  static let home = FeatureDescriptor(id: "home", title: "Home", symbol: "house")
  static let timer = FeatureDescriptor(
    id: "timer", title: "Timer", symbol: "timer",
    permissionNeeds: [PermissionNeed(.notifications, reason: "Tells you when a timer ends.")]
  )
  static let tasks = FeatureDescriptor(
    id: "tasks", title: "Tasks", symbol: "checklist",
    permissionNeeds: [PermissionNeed(.screenRecording, reason: "Turns a screenshot into a new task.")]
  )
  static let clipboard = FeatureDescriptor(
    id: "clipboard", title: "Clipboard", symbol: "doc.on.clipboard",
    permissionNeeds: [PermissionNeed(.pasteboard, reason: "Keeps your clipboard history.")]
  )
  static let keys = FeatureDescriptor(
    id: "secrets", title: "Keys", symbol: "key.horizontal",
    permissionNeeds: [PermissionNeed(.notifications, reason: "Shows Claude's key requests when the window is closed.")]
  )
  static let all = [home, timer, tasks, clipboard, keys]

  static let allOff = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, PermissionStatus.notGranted) })
  static let allOn = Dictionary(uniqueKeysWithValues: Permission.allCases.map { ($0, PermissionStatus.granted) })
}

/// What a client was asked, in order. A test awaits each call it expects with `next()` instead of sleeping, so it
/// passes the same way on a loaded machine; a call that never comes gives nil after `timeout` instead of hanging the
/// run. Effects of one action reach their clients in no set order, so each test expects at most one call per action
/// from one log.
final class CallLog: Sendable {
  private struct Waiter {
    var id: Int
    var continuation: CheckedContinuation<String?, Never>
  }

  private struct State {
    var all: [String] = []
    var pending: [String] = []
    var waiter: Waiter?
    var nextID = 0
  }

  private let state = LockIsolated(State())

  /// Every call so far, taken or not.
  var all: [String] { state.value.all }

  func record(_ call: String) {
    let waiter = state.withValue { state -> Waiter? in
      state.all.append(call)
      guard let waiter = state.waiter else {
        state.pending.append(call)
        return nil
      }
      state.waiter = nil
      return waiter
    }
    waiter?.continuation.resume(returning: call)
  }

  /// The oldest call not taken yet, waiting for it if needed; nil if none comes within `timeout`.
  func next(timeout: Duration = .seconds(5)) async -> String? {
    await withCheckedContinuation { continuation in
      let (taken, id) = state.withValue { state -> (String?, Int) in
        if !state.pending.isEmpty { return (state.pending.removeFirst(), -1) }
        state.nextID += 1
        state.waiter = Waiter(id: state.nextID, continuation: continuation)
        return (nil, state.nextID)
      }
      if let taken {
        continuation.resume(returning: taken)
        return
      }
      Task { [state] in
        try? await Task.sleep(for: timeout)
        let expired = state.withValue { state -> Waiter? in
          guard let waiter = state.waiter, waiter.id == id else { return nil }
          state.waiter = nil
          return waiter
        }
        expired?.continuation.resume(returning: nil)
      }
    }
  }

  /// Calls recorded and not taken yet; for checking that nothing more came once the expected calls are in.
  var untaken: [String] { state.value.pending }
}
