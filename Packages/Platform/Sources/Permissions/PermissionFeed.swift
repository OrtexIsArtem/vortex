import ComposableArchitecture
import Foundation
import VortexCore

/// The scheduling behind the live client, apart from macOS, so tests can drive it with their own read and clock:
/// - reads run one at a time; wake-ups that come during a read make one more read after it, so a burst costs one read;
/// - listeners hear only changes, and a new listener gets the last statuses at once;
/// - while frequent checks are on, it reads once a second, and never otherwise.
final class PermissionFeed: Sendable {
  typealias Statuses = [Permission: PermissionStatus]

  private struct State {
    /// The last statuses read; listeners hear only changes.
    var latest: Statuses?
    var listeners: [UUID: AsyncStream<Statuses>.Continuation] = [:]
    /// Callers of `statuses()` waiting for the next read.
    var waitingForRead: [CheckedContinuation<Statuses, Never>] = []
    var frequentChecks: Task<Void, Never>?
  }

  private let state = LockIsolated(State())
  private let wakeUps: AsyncStream<Void>.Continuation
  private let clock: any Clock<Duration>

  init(clock: any Clock<Duration>, read: @escaping @Sendable () async -> Statuses) {
    let (signals, wakeUps) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    self.wakeUps = wakeUps
    self.clock = clock
    Task { [state] in
      for await _ in signals {
        let callers = state.withValue { state in
          defer { state.waitingForRead = [] }
          return state.waitingForRead
        }
        let statuses = await read()
        state.withValue { state in
          guard statuses != state.latest else { return }
          state.latest = statuses
          for listener in state.listeners.values {
            listener.yield(statuses)
          }
        }
        for caller in callers {
          caller.resume(returning: statuses)
        }
      }
    }
  }

  deinit {
    wakeUps.finish()
    state.value.frequentChecks?.cancel()
  }

  /// Reads every status now, after a read that is running.
  func statuses() async -> Statuses {
    await withCheckedContinuation { continuation in
      state.withValue { $0.waitingForRead.append(continuation) }
      wakeUps.yield()
    }
  }

  /// The statuses now, and again on every change. The listener is in place before the stream is returned, and leaves
  /// as its consumer stops, so none stays behind.
  func updates() -> AsyncStream<Statuses> {
    let (stream, continuation) = AsyncStream.makeStream(of: Statuses.self, bufferingPolicy: .bufferingNewest(1))
    let id = UUID()
    continuation.onTermination = { [state] _ in
      state.withValue { _ = $0.listeners.removeValue(forKey: id) }
    }
    state.withValue { state in
      if let latest = state.latest { continuation.yield(latest) }
      state.listeners[id] = continuation
    }
    wakeUps.yield()
    return stream
  }

  func wakeUp() {
    wakeUps.yield()
  }

  func wakeUp(after delay: Duration) {
    Task { [clock, wakeUps] in
      try? await clock.sleep(for: delay)
      wakeUps.yield()
    }
  }

  /// Reads at once and then once a second while on; off, it doesn't poll.
  func setFrequentChecks(_ isOn: Bool) {
    let timer: Task<Void, Never>? = isOn
      ? Task { [clock, wakeUps] in
        while true {
          do { try await clock.sleep(for: .seconds(1)) } catch { return }
          wakeUps.yield()
        }
      }
      : nil
    state.withValue { state in
      state.frequentChecks?.cancel()
      state.frequentChecks = timer
    }
    if isOn { wakeUps.yield() }
  }

  /// For tests.
  var listenerCount: Int { state.value.listeners.count }
}
