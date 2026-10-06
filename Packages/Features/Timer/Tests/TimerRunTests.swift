import Foundation
import Testing

@testable import FeatureTimer

struct TimerRunTests {
  let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

  @Test
  func countsDownInWholeSecondsRoundedUp() {
    let run = TimerRun.started(minutes: 25, at: start)
    #expect(run.secondsLeft(at: start) == 1500)
    #expect(run.secondsLeft(at: start + 0.5) == 1500)
    #expect(run.secondsLeft(at: start + 1) == 1499)
    #expect(run.fractionLeft(at: start + 750) == 0.5)
    #expect(!run.isOver(at: start + 1499.5))
    #expect(run.isOver(at: start + 1500))
    #expect(run.isOver(at: start + 1600))
  }

  @Test
  func wakesAtTheNextWholeSecondOfTheTimeLeft() {
    let run = TimerRun.started(minutes: 1, at: start)
    #expect(run.untilNextSecond(at: start) == 1)
    #expect(abs(run.untilNextSecond(at: start + 0.25) - 0.75) < 0.000_001)
  }

  @Test
  func pausingKeepsTheTimeLeftUntilResumed() {
    var run = TimerRun.started(minutes: 10, at: start)
    run.pause(at: start + 3)
    #expect(run.phase == .paused(remaining: 597))
    #expect(!run.isOver(at: start + 10_000))
    run.resume(at: start + 100)
    #expect(run.phase == .running(endsAt: start + 697))
  }

  @Test
  func fiveMoreMinutesGoToTheTimeLeftAndTheTotal() {
    var running = TimerRun.started(minutes: 25, at: start)
    running.add(300)
    #expect(running.phase == .running(endsAt: start + 1800))
    #expect(running.totalMinutes == 30)
    var paused = TimerRun(phase: .paused(remaining: 60), total: 600)
    paused.add(300)
    #expect(paused == TimerRun(phase: .paused(remaining: 360), total: 900))
  }

  @Test
  func clockTextReadsLikeAClock() {
    #expect(TimerRun.clockText(seconds: 1500) == "25:00")
    #expect(TimerRun.clockText(seconds: 522) == "8:42")
    #expect(TimerRun.clockText(seconds: 5) == "0:05")
    #expect(TimerRun.clockText(seconds: 3900) == "1:05:00")
  }

  @Test
  func anUnreadableSavedRunIsNoRun() throws {
    #expect(TimerRun.decodeSaved(Data("null".utf8)) == nil)
    #expect(TimerRun.decodeSaved(Data(#"{"phase": 1}"#.utf8)) == nil)
    let run = TimerRun.started(minutes: 5, at: start)
    #expect(TimerRun.decodeSaved(try JSONEncoder().encode(run)) == run)
  }

  /// A saved run as the file holds it: the phase as JSON and the total in seconds.
  func saved(_ phase: String, total: String = "300") -> TimerRun? {
    TimerRun.decodeSaved(Data(#"{"phase":\#(phase),"total":\#(total)}"#.utf8))
  }

  @Test
  func aSavedRunWithImpossibleValuesIsNoRun() {
    // Each of these once decoded as a run and then stopped Vortex with a crash at every launch.
    #expect(saved(#"{"running":{"endsAt":1e300}}"#) == nil)
    #expect(saved(#"{"running":{"endsAt":-1e300}}"#) == nil)
    #expect(saved(#"{"paused":{"remaining":-1e30}}"#) == nil)
    #expect(saved(#"{"paused":{"remaining":1e300}}"#, total: "1e300") == nil)
    // A time left below zero or above the total.
    #expect(saved(#"{"paused":{"remaining":-1}}"#) == nil)
    #expect(saved(#"{"paused":{"remaining":301}}"#) == nil)
    // An end beyond the dates a run can have.
    #expect(saved(#"{"running":{"endsAt":1000000001}}"#) == nil)
    #expect(saved(#"{"running":{"endsAt":-1000000001}}"#) == nil)
    // A total that is no run: nothing, below nothing, over a day.
    for total in ["0", "-300", "86401", "1e300"] {
      #expect(saved(#"{"running":{"endsAt":800000300}}"#, total: total) == nil)
    }
  }

  @Test
  func theEdgesOfWhatIsPossibleAreStillARun() {
    #expect(saved(#"{"running":{"endsAt":800000300}}"#) != nil)
    #expect(saved(#"{"running":{"endsAt":1000000000}}"#, total: "86400") != nil)
    #expect(saved(#"{"running":{"endsAt":-1000000000}}"#, total: "1") != nil)
    #expect(saved(#"{"paused":{"remaining":0}}"#) != nil)
    #expect(saved(#"{"paused":{"remaining":300}}"#) != nil)
    #expect(saved(#"{"paused":{"remaining":86400}}"#, total: "86400") != nil)
  }

  @Test
  func valuesThatAreNoNumbersAreNotPossible() {
    // JSON can't carry these; only code can, but the check should not depend on that.
    let nan = Double.nan
    let infinity = Double.infinity
    #expect(!TimerRun(phase: .running(endsAt: start), total: nan).hasPossibleValues)
    #expect(!TimerRun(phase: .running(endsAt: start), total: infinity).hasPossibleValues)
    #expect(!TimerRun(phase: .running(endsAt: Date(timeIntervalSinceReferenceDate: nan)), total: 300).hasPossibleValues)
    #expect(!TimerRun(phase: .running(endsAt: Date(timeIntervalSinceReferenceDate: infinity)), total: 300).hasPossibleValues)
    #expect(!TimerRun(phase: .paused(remaining: nan), total: 300).hasPossibleValues)
    #expect(!TimerRun(phase: .paused(remaining: infinity), total: .infinity).hasPossibleValues)
    #expect(TimerRun.started(minutes: 25, at: start).hasPossibleValues)
  }

  @Test
  func theTimeLeftIsNeverMoreThanTheTotal() {
    // The clock was set back after the start: the end is now further off than the run is long.
    let run = TimerRun(phase: .running(endsAt: start + 10_000), total: 300)
    #expect(run.remaining(at: start) == 300)
    #expect(run.secondsLeft(at: start) == 300)
    #expect(run.fractionLeft(at: start) == 1)
    #expect(!run.isOver(at: start))
    // The farthest end a saved run may have, seen from a date far in the past: no overflow, still no more than the total.
    let farthest = TimerRun(phase: .running(endsAt: Date(timeIntervalSinceReferenceDate: TimerRun.farthestEnd)), total: 300)
    #expect(farthest.secondsLeft(at: start) == 300)
    #expect(farthest.secondsLeft(at: .distantPast) == 300)
    // And never below zero, whichever the phase.
    #expect(run.remaining(at: start + 20_000) == 0)
    #expect(TimerRun(phase: .paused(remaining: 500), total: 300).remaining(at: start) == 300)
    #expect(TimerRun(phase: .paused(remaining: -5), total: 300).remaining(at: start) == 0)
  }

  @Test
  func pausingAfterTheClockWasSetBackKeepsNoMoreThanTheTotal() {
    var run = TimerRun(phase: .running(endsAt: start + 10_000), total: 300)
    run.pause(at: start)
    #expect(run.phase == .paused(remaining: 300))
    #expect(run.hasPossibleValues)
  }
}
