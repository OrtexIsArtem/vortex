import ComposableArchitecture
import Foundation
import os
import VortexCore
import VortexPlatform

/// One timer at a time: set on the drum or picked from the quick starts, shown in the closed notch; when time is up, a
/// sound, a notification with "+5 min", and the notch flashes until the user looks at it. It goes on while the window is
/// closed and after a relaunch.
@Reducer
public struct TimerFeature: Sendable {
  public static let id: FeatureID = "timer"
  /// The minutes the drum turns through.
  static let minuteRange = 1...120
  /// Where the drum stands whenever it shows, whatever was set on it before.
  static let defaultMinutes = 5
  /// The Timer tab's quick starts: one click starts a run of that many minutes.
  static let quickStarts = [5, 10, 15, 30, 60]
  /// "+5 min" on the notification that time is up starts a run of this many minutes.
  static let addedMinutes = 5
  static let doneNotificationID = "timer.done"
  static let addFiveButtonID = "timer.addFive"

  @ObservableState
  public struct State: Equatable {
    @Shared(.timerSettings) var settings
    @Shared(.timerRun) var run
    @Shared(.notchIndicators) var indicators
    /// The feature is on, see `FeatureModule.setEnabled`.
    var isEnabled = false
    /// Set on every tick, so the views and the notch show the time left.
    var now = Date.distantPast
    /// Grows by one when time is up and on every test, so each is a new alarm in the notch.
    var alarms = 0
    /// The last alarm flashes the notch until the user sees it; a new run ends it.
    var isAlarming = false
    /// System sounds, for the settings.
    var sounds: [String] = []

    public init() {}

    /// The ring (or pause) and the time left in the closed notch. Without a run it shows no ears but can still flash.
    var indicator: NotchIndicator? {
      guard isEnabled else { return nil }
      let alarm = isAlarming ? alarms : nil
      guard let run else {
        return NotchIndicator(leading: [], trailing: [], priority: 10, flashColor: settings.flashColor, alarm: alarm)
      }
      return NotchIndicator(
        leading: [run.isPaused ? .symbol("pause.fill") : .progress(run.fractionLeft(at: now))],
        trailing: [.text(TimerRun.clockText(seconds: run.secondsLeft(at: now)))],
        priority: 10,
        flashColor: settings.flashColor,
        alarm: alarm
      )
    }
  }

  public enum Action: Equatable, Sendable {
    case start
    case stop
    /// Start under the drum, or a quick start: a run of that many minutes, kept within the drum's range.
    case startTapped(minutes: Int)
    case pauseTapped
    case resumeTapped
    case stopTapped
    case tick
    /// The shared run changed: by this feature, or from outside it, such as another Vortex writing the run file or the
    /// file edited or deleted.
    case runChanged
    case notificationButtonPressed(String)
    case settingsShown
    case soundsLoaded([String])
    case soundChosen(String?)
    case flashColorChanged(ColorValue)
    /// Plays the sound and starts the flashes three seconds later, so the window can be closed first.
    case testTapped
    case testAlarm
  }

  @Dependency(\.continuousClock) var clock
  @Dependency(\.date.now) var now
  @Dependency(\.notificationClient) var notifications
  @Dependency(\.soundClient) var sounds

  private enum CancelID {
    case tick
    case runChanges
    case buttons
    case test
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .start:
        state.isEnabled = true
        state.now = now
        // A run that ran out while Vortex was closed is over: nobody was there to hear it.
        var dropped = Effect<Action>.none
        if state.run?.isOver(at: state.now) == true {
          state.$run.withLock { $0 = nil }
          dropped = saveRun(state)
        }
        return .merge(listenToNotificationButtons(), followRunChanges(state), tick(state), dropped)

      case .stop:
        state.isEnabled = false
        state.isAlarming = false
        state.$run.withLock { $0 = nil }
        return .merge(
          saveRun(state),
          .cancel(id: CancelID.tick),
          .cancel(id: CancelID.runChanges),
          .cancel(id: CancelID.buttons),
          .cancel(id: CancelID.test)
        )

      case let .startTapped(minutes):
        return startRun(minutes: Self.clampedMinutes(minutes), &state)

      case .pauseTapped:
        let now = self.now
        state.now = now
        state.$run.withLock { $0?.pause(at: now) }
        return .merge(.cancel(id: CancelID.tick), saveRun(state))

      case .resumeTapped:
        let now = self.now
        state.now = now
        state.$run.withLock { $0?.resume(at: now) }
        return .merge(tick(state), saveRun(state))

      case .stopTapped:
        state.$run.withLock { $0 = nil }
        return .merge(.cancel(id: CancelID.tick), saveRun(state))

      case .tick:
        state.now = now
        guard state.run?.isOver(at: state.now) == true else { return .none }
        return timeIsUp(&state)

      case .runChanged:
        // A change from outside reached the state without an action: the time, the notch and the ticks follow the run
        // here. This feature's own changes come here too, a moment later, and find them in step; setting the ticks
        // again does no harm, as they keep to the whole seconds of the time left.
        state.now = now
        let indicator = state.indicator
        if state.indicators[Self.id] != indicator {
          // `.onChange` below compares the state before and after an action, so it never sees such a change.
          state.$indicators.withLock { $0[Self.id] = indicator }
        }
        return tick(state)

      case let .notificationButtonPressed(button):
        // "+5 min" on the notification that time is up: five more minutes, as a new run.
        guard button == Self.addFiveButtonID else { return .none }
        return startRun(minutes: Self.addedMinutes, &state)

      case .settingsShown:
        return .run { send in await send(.soundsLoaded(await sounds.names())) }

      case let .soundsLoaded(names):
        state.sounds = names
        return .none

      case let .soundChosen(sound):
        state.$settings.withLock { $0.sound = sound }
        guard let sound else { return .none }
        return .run { _ in await sounds.play(sound) }

      case let .flashColorChanged(color):
        state.$settings.withLock { $0.flashColor = color }
        return .none

      case .testTapped:
        return .run { send in
          try await clock.sleep(for: .seconds(3))
          await send(.testAlarm)
        }
        .cancellable(id: CancelID.test, cancelInFlight: true)

      case .testAlarm:
        return alarm(&state)
      }
    }
    .onChange(of: \.indicator) { _, indicator in
      Reduce { state, _ in
        state.$indicators.withLock { $0[Self.id] = indicator }
        return .none
      }
    }
  }

  /// Within `minuteRange`.
  static func clampedMinutes(_ minutes: Int) -> Int {
    min(max(minutes, minuteRange.lowerBound), minuteRange.upperBound)
  }

  /// Starts a run unless one is going: one timer at a time. A new run ends the alarm of the last one.
  private func startRun(minutes: Int, _ state: inout State) -> Effect<Action> {
    guard state.isEnabled, state.run == nil else { return .none }
    let now = self.now
    state.now = now
    state.isAlarming = false
    state.$run.withLock { $0 = TimerRun.started(minutes: minutes, at: now) }
    // Never asks whether Vortex may notify (S25): without Notifications the end shows in the notch only, and the
    // settings row offers the page.
    return .merge(tick(state), saveRun(state))
  }

  /// Sends `runChanged` whenever the shared run changes. A change from outside the reducer (another Vortex, the run
  /// file edited or deleted) sets the shared value without any action, so the ticks and the notch would not follow it.
  private func followRunChanges(_ state: State) -> Effect<Action> {
    .run { [run = state.$run] send in
      // The publisher reports a change before the new value is stored, so the action is sent from here, a moment
      // later. Only the newest change is kept: the action reads the run from the state.
      let (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
      let subscription = run.publisher
        .removeDuplicates()
        // The run as it is now.
        .dropFirst()
        .sink { _ in continuation.yield() }
      defer { subscription.cancel() }
      for await _ in changes {
        await send(.runChanged)
      }
    }
    .cancellable(id: CancelID.runChanges, cancelInFlight: true)
  }

  /// Writes the run file at once; every change of the run returns it. On its own the shared run writes a change at once
  /// only a second after the previous write, a sooner one when that second is over, and a quit or a kill before then
  /// would lose it: after a relaunch a stopped run would come back, or a paused one go on.
  private func saveRun(_ state: State) -> Effect<Action> {
    .run { [run = state.$run] _ in
      try await run.save()
    } catch: { error, _ in
      logger.error("Saving the timer run failed: \(error, privacy: .public)")
    }
  }

  /// A tick at every whole second of the time left while a run is going.
  private func tick(_ state: State) -> Effect<Action> {
    guard state.isEnabled, let run = state.run, !run.isPaused else { return .cancel(id: CancelID.tick) }
    let first = Duration.milliseconds(Int((run.untilNextSecond(at: state.now) * 1000).rounded(.up)))
    return .run { send in
      try await clock.sleep(for: first)
      await send(.tick)
      for await _ in clock.timer(interval: .seconds(1)) {
        await send(.tick)
      }
    }
    .cancellable(id: CancelID.tick, cancelInFlight: true)
  }

  /// The run is over: the alarm, and a notification with "+5 min".
  private func timeIsUp(_ state: inout State) -> Effect<Action> {
    let minutes = state.run?.totalMinutes ?? 0
    state.$run.withLock { $0 = nil }
    let title = String(localized: "Time's up", bundle: .module)
    let body = String(localized: "The \(minutes)-minute timer is done", bundle: .module)
    let addFive = NotificationClient.Button(id: Self.addFiveButtonID, title: String(localized: "+5 min", bundle: .module))
    return .merge(
      .cancel(id: CancelID.tick),
      saveRun(state),
      alarm(&state),
      .run { _ in await notifications.post(Self.doneNotificationID, title, body, [addFive]) }
    )
  }

  /// The sound, and a new alarm: the shell flashes the notch until the user looks at it.
  private func alarm(_ state: inout State) -> Effect<Action> {
    state.alarms += 1
    state.isAlarming = true
    guard let sound = state.settings.sound else { return .none }
    return .run { _ in await sounds.play(sound) }
  }

  private func listenToNotificationButtons() -> Effect<Action> {
    .run { send in
      for await press in await notifications.buttonPresses() where press.notification == Self.doneNotificationID {
        await send(.notificationButtonPressed(press.button))
      }
    }
    .cancellable(id: CancelID.buttons, cancelInFlight: true)
  }
}

private let logger = Logger(subsystem: "io.github.ortexisartem.vortex", category: "timer")
