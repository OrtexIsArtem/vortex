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
}
