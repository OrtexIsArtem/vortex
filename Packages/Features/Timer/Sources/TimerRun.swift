import ComposableArchitecture
import Foundation
import VortexCore

/// A timer that was started and has not been stopped or run out yet. Saved, so it goes on after a relaunch of Vortex.
public struct TimerRun: Codable, Equatable, Sendable {
  public enum Phase: Codable, Equatable, Sendable {
    case running(endsAt: Date)
    case paused(remaining: TimeInterval)
  }

  public var phase: Phase
  /// The minutes started, in seconds: the ring shows the time left out of it.
  public var total: TimeInterval

  public init(phase: Phase, total: TimeInterval) {
    self.phase = phase
    self.total = total
  }

  /// A run of `minutes` that starts at `now`.
  static func started(minutes: Int, at now: Date) -> TimerRun {
    let seconds = TimeInterval(minutes * 60)
    return TimerRun(phase: .running(endsAt: now.addingTimeInterval(seconds)), total: seconds)
  }

  var isPaused: Bool {
    if case .paused = phase { true } else { false }
  }

  /// Seconds left: never below zero, and never more than the total, which a clock set back would otherwise exceed.
  func remaining(at now: Date) -> TimeInterval {
    switch phase {
    case let .running(endsAt): min(max(endsAt.timeIntervalSince(now), 0), total)
    case let .paused(remaining): min(max(remaining, 0), total)
    }
  }

  /// Whole seconds left, rounded up, so 25:00 shows until a full second has passed. A millisecond is forgiven:
  /// the clock may wake a hair early.
  func secondsLeft(at now: Date) -> Int {
    max(Int((remaining(at: now) - 0.001).rounded(.up)), 0)
  }

  /// Time is up once no whole second is left; a paused run never runs out.
  func isOver(at now: Date) -> Bool {
    !isPaused && secondsLeft(at: now) == 0
  }

  /// Time left out of the total, 0…1.
  func fractionLeft(at now: Date) -> Double {
    total > 0 ? min(max(remaining(at: now) / total, 0), 1) : 0
  }

  /// How long until the shown time changes: until the time left reaches its next whole second.
  func untilNextSecond(at now: Date) -> TimeInterval {
    let remaining = remaining(at: now)
    let fraction = remaining - remaining.rounded(.down)
    return fraction < 0.001 ? 1 : fraction
  }

  /// The total in whole minutes, for "of 25 min".
  var totalMinutes: Int {
    Int((total / 60).rounded())
  }

  mutating func pause(at now: Date) {
    guard !isPaused else { return }
    phase = .paused(remaining: remaining(at: now))
  }

  mutating func resume(at now: Date) {
    guard case let .paused(remaining) = phase else { return }
    phase = .running(endsAt: now.addingTimeInterval(remaining))
  }

  /// "25:00", "8:42", "0:05"; an hour or more "1:05:00".
  static func clockText(seconds: Int) -> String {
    let (hours, minutes, rest) = (seconds / 3600, seconds % 3600 / 60, seconds % 60)
    return hours > 0
      ? String(format: "%ld:%02ld:%02ld", hours, minutes, rest)
      : String(format: "%ld:%02ld", minutes, rest)
  }

  /// The longest a run can be: a day.
  static let longestTotal: TimeInterval = 24 * 60 * 60

  /// Whether the values are possible for a run. Anything else comes from a damaged or hand-edited file, and would
  /// stop the whole-second arithmetic of a launch with a crash. The end of a running run has no bound of its own, only
  /// that it is a number: `remaining(at:)` keeps the time left within 0...total, so no date, however far off, reaches
  /// the arithmetic. (A bound on the date would sooner or later turn every saved run into no run.)
  var hasPossibleValues: Bool {
    guard total.isFinite, total > 0, total <= Self.longestTotal else { return false }
    switch phase {
    case let .running(endsAt):
      return endsAt.timeIntervalSinceReferenceDate.isFinite
    case let .paused(remaining):
      return remaining.isFinite && remaining >= 0 && remaining <= total
    }
  }

  /// A saved run, or nil when the file holds none, can't be read or holds impossible values.
  static func decodeSaved(_ data: Data) -> TimerRun? {
    guard let run = try? JSONDecoder().decode(TimerRun.self, from: data), run.hasPossibleValues else { return nil }
    return run
  }
}

extension SharedKey where Self == FileStorageKey<TimerRun?>.Default {
  /// DataFolder/Timer/run.json. An unreadable file means no run.
  static var timerRun: Self {
    Self[
      .fileStorage(
        DataFolder.url.appending(path: "Timer/run.json"),
        decode: { TimerRun.decodeSaved($0) },
        encode: { try JSONEncoder().encode($0) }
      ),
      default: nil
    ]
  }
}
