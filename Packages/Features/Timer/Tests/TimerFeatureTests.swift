import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureTimer
// A file storage whose delayed writes never happen.
@_spi(Internals) import Sharing

@MainActor
struct TimerFeatureTests {
  let clock = TestClock()
  let now = LockIsolated(Date(timeIntervalSinceReferenceDate: 800_000_000))
  let played = LockIsolated<[String]>([])
  /// "notification id:button ids".
  let posted = LockIsolated<[String]>([])
  let authorizations = LockIsolated(0)
  let buttons = AsyncStream.makeStream(of: NotificationClient.Press.self)

  func makeStore() -> TestStoreOf<TimerFeature> {
    let store = TestStore(initialState: TimerFeature.State()) {
      TimerFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.date = DateGenerator { [now] in now.value }
      $0.soundClient.names = { ["Basso", "Glass"] }
      $0.soundClient.play = { [played] name in played.withValue { $0.append(name) } }
      $0.notificationClient.requestAuthorization = { [authorizations] in
        authorizations.withValue { $0 += 1 }
        return true
      }
      $0.notificationClient.post = { [posted] id, _, _, buttons in
        posted.withValue { $0.append("\(id):\(buttons.map(\.id).joined(separator: ","))") }
      }
      $0.notificationClient.buttonPresses = { [buttons] in buttons.stream }
      $0.permissionsClient.refresh = {}
    }
    store.exhaustivity = .off
    return store
  }

  /// Start under the drum, or a quick start.
  func startRun(_ store: TestStoreOf<TimerFeature>, minutes: Int) async {
    await store.send(.startTapped(minutes: minutes))
  }

  /// Moves the date the feature reads and the clock its effects sleep on.
  func pass(_ seconds: Int) async {
    now.withValue { $0 += TimeInterval(seconds) }
    await clock.advance(by: .seconds(seconds))
  }

  @Test
  func startStartsTheMinutesAskedForAndTicksInTheNotch() async {
    let store = makeStore()
    await store.send(.start)
    await startRun(store, minutes: 25)
    #expect(store.state.run == TimerRun.started(minutes: 25, at: now.value))
    @Shared(.notchIndicators) var indicators
    #expect(indicators[TimerFeature.id]?.leading == [.progress(1)])
    #expect(indicators[TimerFeature.id]?.trailing == [.text("25:00")])
    #expect(indicators[TimerFeature.id]?.priority == 10)
    await pass(1)
    await store.receive(\.tick)
    #expect(indicators[TimerFeature.id]?.trailing == [.text("24:59")])
    // A run never asks whether Vortex may notify (S25).
    #expect(authorizations.value == 0)
    await store.send(.stop)
    #expect(indicators[TimerFeature.id] == nil)
  }

  @Test
  func pausingStopsTheClockUntilResumed() async {
    let store = makeStore()
    await store.send(.start)
    await startRun(store, minutes: 10)
    await pass(3)
    await store.send(.pauseTapped)
    #expect(store.state.run?.phase == .paused(remaining: 597))
    @Shared(.notchIndicators) var indicators
    #expect(indicators[TimerFeature.id]?.leading == [.symbol("pause.fill")])
    await pass(60)
    #expect(store.state.run?.phase == .paused(remaining: 597))
    await store.send(.resumeTapped)
    #expect(store.state.run?.phase == .running(endsAt: now.value + 597))
    await pass(1)
    await store.receive(\.tick)
    #expect(indicators[TimerFeature.id]?.trailing == [.text("9:56")])
    await store.send(.stop)
  }

  @Test
  func stopEndsTheRunQuietly() async {
    let store = makeStore()
    await store.send(.start)
    await startRun(store, minutes: 5)
    await store.send(.stopTapped)
    #expect(store.state.run == nil)
    @Shared(.notchIndicators) var indicators
    #expect(indicators[TimerFeature.id] == NotchIndicator(
      leading: [], trailing: [], priority: 10, flashColor: TimerSettings.defaultFlashColor
    ))
    await pass(600)
    #expect(played.value.isEmpty)
    await store.send(.stop)
  }

  @Test
  func whenTimeIsUpItPlaysTheSoundNotifiesAndRaisesAnAlarmInTheNotch() async {
    let store = makeStore()
    await store.send(.start)
    await startRun(store, minutes: 5)
    await pass(300)
    await store.receive(\.tick)
    #expect(store.state.run == nil)
    @Shared(.notchIndicators) var indicators
    #expect(indicators[TimerFeature.id] == NotchIndicator(
      leading: [], trailing: [], priority: 10, flashColor: TimerSettings.defaultFlashColor, alarm: 1
    ))
    // The shell flashes the notch until the user sees it; the next run ends the alarm either way.
    await startRun(store, minutes: 5)
    #expect(indicators[TimerFeature.id]?.alarm == nil)
    await store.send(.stop)
    await store.finish()
    #expect(played.value == [TimerSettings.defaultSound])
    #expect(posted.value == ["\(TimerFeature.doneNotificationID):\(TimerFeature.addFiveButtonID)"])
  }

  @Test
  func plusFiveOnTheNotificationEndsTheAlarm() async {
    let store = makeStore()
    await store.send(.start)
    await startRun(store, minutes: 5)
    await pass(300)
    await store.receive(\.tick)
    @Shared(.notchIndicators) var indicators
    #expect(indicators[TimerFeature.id]?.alarm == 1)
    buttons.continuation.yield(NotificationClient.Press(notification: TimerFeature.doneNotificationID, button: TimerFeature.addFiveButtonID))
    await store.receive(\.notificationButtonPressed)
    #expect(indicators[TimerFeature.id]?.alarm == nil)
    await store.send(.stop)
  }

  @Test
  func aRunSavedBeforeARelaunchGoesOn() async {
    @Shared(.timerRun) var run
    $run.withLock { $0 = TimerRun(phase: .running(endsAt: now.value + 90), total: 300) }
    let store = makeStore()
    await store.send(.start)
    @Shared(.notchIndicators) var indicators
    #expect(indicators[TimerFeature.id]?.trailing == [.text("1:30")])
    await pass(1)
    await store.receive(\.tick)
    #expect(indicators[TimerFeature.id]?.trailing == [.text("1:29")])
    await store.send(.stop)
  }

  @Test
  func aRunThatRanOutWhileVortexWasClosedIsDroppedQuietly() async {
    @Shared(.timerRun) var run
    $run.withLock { $0 = TimerRun(phase: .running(endsAt: now.value - 60), total: 300) }
    let store = makeStore()
    await store.send(.start)
    #expect(store.state.run == nil)
    await pass(5)
    #expect(played.value.isEmpty)
    await store.send(.stop)
  }

  @Test
  func aRunEndedOutsideTheFeatureStopsTheTicksAndLeavesTheNotch() async {
    let store = makeStore()
    await store.send(.start)
    await startRun(store, minutes: 25)
    await pass(1)
    await store.receive(\.tick)
    // Another Vortex stops the run, or the run file is deleted: the shared run changes without an action.
    @Shared(.timerRun) var run
    $run.withLock { $0 = nil }
    await store.receive(\.runChanged)
    @Shared(.notchIndicators) var indicators
    #expect(indicators[TimerFeature.id] == NotchIndicator(
      leading: [], trailing: [], priority: 10, flashColor: TimerSettings.defaultFlashColor
    ))
    // No tick comes any more: each would move the time on.
    let stoppedAt = store.state.now
    await pass(5)
    #expect(store.state.now == stoppedAt)
    await store.send(.stop)
  }

  @Test
  func aRunStartedOutsideTheFeatureTicksInTheNotch() async {
    let store = makeStore()
    await store.send(.start)
    // Another Vortex starts a run: the shared run changes without an action.
    @Shared(.timerRun) var run
    $run.withLock { $0 = TimerRun(phase: .running(endsAt: now.value + 90), total: 300) }
    await store.receive(\.runChanged)
    @Shared(.notchIndicators) var indicators
    #expect(indicators[TimerFeature.id]?.leading == [.progress(0.3)])
    #expect(indicators[TimerFeature.id]?.trailing == [.text("1:30")])
    await pass(1)
    await store.receive(\.tick)
    #expect(indicators[TimerFeature.id]?.trailing == [.text("1:29")])
    await store.send(.stop)
  }

  @Test
  func everyChangeOfTheRunIsWrittenToItsFileAtOnce() async {
    // The shared run writes a change at once only a second after the previous write. This storage never lets that second
    // end, as when Vortex quits or is killed right after a change.
    let files = LockIsolated<[URL: Data]>([:])
    /// What the run file holds.
    func saved() -> Data? { files.value.first { $0.key.lastPathComponent == "run.json" }?.value }
    await withDependencies {
      $0.defaultFileStorage = .inMemory(fileSystem: files, asyncAfter: { _, _ in })
    } operation: {
      let store = makeStore()
      await store.send(.start)
      await startRun(store, minutes: 25)
      await store.send(.pauseTapped).finish()
      #expect(saved().flatMap(TimerRun.decodeSaved) == TimerRun(phase: .paused(remaining: 1500), total: 1500))
      await store.send(.stopTapped).finish()
      #expect(saved() == Data("null".utf8))
      await store.send(.stop)
    }
  }

  @Test
  func plusFiveOnTheNotificationStartsFiveMoreMinutes() async {
    let store = makeStore()
    await store.send(.start)
    buttons.continuation.yield(NotificationClient.Press(notification: TimerFeature.doneNotificationID, button: TimerFeature.addFiveButtonID))
    await store.receive(\.notificationButtonPressed)
    #expect(store.state.run == TimerRun.started(minutes: 5, at: now.value))
    await store.send(.stop)
  }

  @Test
  func oneTimerAtATime() async {
    let store = makeStore()
    await store.send(.start)
    let startedAt = now.value
    await startRun(store, minutes: 25)
    await pass(60)
    await store.send(.startTapped(minutes: 5))
    // Neither Start nor "+5 min" on a notification replaces the run going.
    buttons.continuation.yield(NotificationClient.Press(notification: TimerFeature.doneNotificationID, button: TimerFeature.addFiveButtonID))
    await store.receive(\.notificationButtonPressed)
    #expect(store.state.run == TimerRun.started(minutes: 25, at: startedAt))
    await store.send(.stop)
  }

  @Test
  func aStartIsKeptWithinTheDrumsRange() async {
    let store = makeStore()
    await store.send(.start)
    await startRun(store, minutes: 0)
    #expect(store.state.run?.total == 60)
    await store.send(.stopTapped)
    await startRun(store, minutes: 500)
    #expect(store.state.run?.total == TimeInterval(120 * 60))
    await store.send(.stop)
    #expect(TimerFeature.clampedMinutes(-7) == 1)
    #expect(TimerFeature.clampedMinutes(TimerFeature.defaultMinutes + 10) == 15)
  }

  @Test
  func settingsPlayTheChosenSound() async {
    let store = makeStore()
    await store.send(.settingsShown)
    await store.receive(\.soundsLoaded) { $0.sounds = ["Basso", "Glass"] }
    await store.send(.soundChosen("Basso"))
    #expect(store.state.settings.sound == "Basso")
    await store.send(.soundChosen(nil))
    #expect(store.state.settings.sound == nil)
    await store.finish()
    #expect(played.value == ["Basso"])
  }

  @Test
  func theTestPlaysTheAlarmThreeSecondsLaterWithoutANotification() async {
    let store = makeStore()
    await store.send(.start)
    await store.send(.testTapped)
    await clock.advance(by: .milliseconds(2999))
    #expect(played.value.isEmpty)
    await clock.advance(by: .milliseconds(1))
    await store.receive(\.testAlarm)
    @Shared(.notchIndicators) var indicators
    #expect(indicators[TimerFeature.id]?.alarm == 1)
    // Each test is a new alarm, even when the last one was never ended.
    await store.send(.testAlarm)
    #expect(indicators[TimerFeature.id]?.alarm == 2)
    await store.send(.stop)
    await store.finish()
    #expect(played.value == [TimerSettings.defaultSound, TimerSettings.defaultSound])
    #expect(posted.value.isEmpty)
  }

  @Test
  func turningTheFeatureOffEndsTheRun() async {
    let store = makeStore()
    await store.send(.start)
    await startRun(store, minutes: 25)
    await store.send(.stop)
    #expect(store.state.run == nil)
    @Shared(.notchIndicators) var indicators
    #expect(indicators[TimerFeature.id] == nil)
  }
}
