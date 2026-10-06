import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureTimer

@MainActor
struct TimerFeatureTests {
  let clock = TestClock()
  let now = LockIsolated(Date(timeIntervalSinceReferenceDate: 800_000_000))
  let played = LockIsolated<[String]>([])
  /// "notification id:button ids".
  let posted = LockIsolated<[String]>([])
  let authorizations = LockIsolated(0)
  let buttons = AsyncStream.makeStream(of: String.self)

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
    }
    store.exhaustivity = .off
    return store
  }

  /// Moves the date the feature reads and the clock its effects sleep on.
  func pass(_ seconds: Int) async {
    now.withValue { $0 += TimeInterval(seconds) }
    await clock.advance(by: .seconds(seconds))
  }

  @Test
  func aPresetStartsARunThatTicksInTheNotch() async {
    let store = makeStore()
    await store.send(.start)
    await store.send(.presetTapped(25))
    #expect(store.state.run == TimerRun.started(minutes: 25, at: now.value))
    #expect(store.state.settings.lastMinutes == 25)
    @Shared(.notchIndicators) var indicators
    #expect(indicators[TimerFeature.id]?.leading == [.progress(1)])
    #expect(indicators[TimerFeature.id]?.trailing == [.text("25:00")])
    #expect(indicators[TimerFeature.id]?.priority == 10)
    await pass(1)
    await store.receive(\.tick)
    #expect(indicators[TimerFeature.id]?.trailing == [.text("24:59")])
    #expect(authorizations.value == 1)
    await store.send(.stop)
    #expect(indicators[TimerFeature.id] == nil)
  }

  @Test
  func pausingStopsTheClockUntilResumed() async {
    let store = makeStore()
    await store.send(.start)
    await store.send(.presetTapped(10))
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
  func fiveMoreMinutesWhileRunningOrPaused() async {
    let store = makeStore()
    await store.send(.start)
    await store.send(.presetTapped(5))
    await store.send(.addFiveMinutesTapped)
    #expect(store.state.run == TimerRun(phase: .running(endsAt: now.value + 600), total: 600))
    await store.send(.pauseTapped)
    await store.send(.addFiveMinutesTapped)
    #expect(store.state.run == TimerRun(phase: .paused(remaining: 900), total: 900))
    await store.send(.stop)
  }

  @Test
  func stopEndsTheRunQuietly() async {
    let store = makeStore()
    await store.send(.start)
    await store.send(.presetTapped(5))
    await store.send(.stopTapped)
    #expect(store.state.run == nil)
    @Shared(.notchIndicators) var indicators
    #expect(indicators[TimerFeature.id] == NotchIndicator(
      leading: [], trailing: [], priority: 10, flash: 0, flashColor: TimerSettings.defaultFlashColor
    ))
    await pass(600)
    #expect(played.value.isEmpty)
    await store.send(.stop)
  }

  @Test
  func whenTimeIsUpItPlaysTheSoundNotifiesAndFlashesThreeTimes() async {
    let store = makeStore()
    await store.send(.start)
    await store.send(.presetTapped(5))
    await pass(300)
    await store.receive(\.tick)
    await store.receive(\.flashDue)
    await store.receive(\.flashDue)
    await store.receive(\.flashDue)
    #expect(store.state.run == nil)
    #expect(store.state.flashes == 3)
    #expect(played.value == [TimerSettings.defaultSound])
    await store.send(.stop)
    await store.finish()
    #expect(posted.value == ["\(TimerFeature.doneNotificationID):\(TimerFeature.addFiveButtonID)"])
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
  func plusFiveOnTheNotificationStartsFiveMoreMinutes() async {
    let store = makeStore()
    await store.send(.start)
    buttons.continuation.yield(TimerFeature.addFiveButtonID)
    await store.receive(\.notificationButtonPressed)
    #expect(store.state.run == TimerRun.started(minutes: 5, at: now.value))
    #expect(store.state.settings.lastMinutes == 25)
    await store.send(.stop)
  }

  @Test
  func oneTimerAtATime() async {
    let store = makeStore()
    await store.send(.start)
    await store.send(.presetTapped(25))
    await store.send(.presetTapped(5))
    #expect(store.state.run?.total == 1500)
    await store.send(.stop)
  }

  @Test
  func theCarouselMovesThroughPresetsAndStartsTheOneShown() async {
    let store = makeStore()
    await store.send(.start)
    #expect(store.state.carouselPreset == 25)
    await store.send(.nextPresetTapped)
    await store.send(.nextPresetTapped)
    await store.send(.nextPresetTapped)
    #expect(store.state.carouselPreset == 60)
    await store.send(.previousPresetTapped)
    #expect(store.state.carouselPreset == 45)
    await store.send(.startTapped)
    #expect(store.state.run?.total == TimeInterval(45 * 60))
    #expect(store.state.settings.lastMinutes == 45)
    await store.send(.stop)
  }

  @Test
  func settingsCleanUpPresetsAndPlayTheChosenSound() async {
    let store = makeStore()
    await store.send(.settingsShown)
    await store.receive(\.soundsLoaded) { $0.sounds = ["Basso", "Glass"] }
    await store.send(.presetsSubmitted("90, 3, x, 3"))
    #expect(store.state.settings.presets == [3, 90])
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
    await store.receive(\.flashDue)
    #expect(played.value == [TimerSettings.defaultSound])
    await clock.advance(by: .seconds(3))
    // The state moves on only when the test receives the actions of the effect.
    await store.receive(\.flashDue)
    await store.receive(\.flashDue)
    #expect(store.state.flashes == 3)
    #expect(posted.value.isEmpty)
    await store.send(.stop)
  }

  @Test
  func turningTheFeatureOffEndsTheRun() async {
    let store = makeStore()
    await store.send(.start)
    await store.send(.presetTapped(25))
    await store.send(.stop)
    #expect(store.state.run == nil)
    @Shared(.notchIndicators) var indicators
    #expect(indicators[TimerFeature.id] == nil)
  }
}
