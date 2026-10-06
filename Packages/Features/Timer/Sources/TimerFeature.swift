import ComposableArchitecture
import Foundation
import os
import VortexCore
import VortexPlatform

/// One timer at a time: started from a preset, shown in the closed notch; when time is up, a sound, a notification
/// with "+5 min" and three flashes of the notch. It goes on while the window is closed and after a relaunch.
@Reducer
public struct TimerFeature: Sendable {
  public static let id: FeatureID = "timer"
  static let addedTime: TimeInterval = 5 * 60
  static let flashesWhenDone = 3
  static let flashInterval: Duration = .milliseconds(1500)
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
    /// The preset the user moved to in the Timer tab, until the tab is shown again; nil shows `settings.initialPreset`.
    var chosenPreset: Int?
    /// Grows by one for every flash of the notch.
    var flashes = 0
    /// System sounds, for the settings.
    var sounds: [String] = []

    public init() {}

    /// The preset the Timer tab shows.
    var carouselPreset: Int {
      if let chosenPreset, settings.presets.contains(chosenPreset) { return chosenPreset }
      return settings.initialPreset
    }

    /// The ring (or pause) and the time left in the closed notch. Without a run it shows no ears but can still flash.
    var indicator: NotchIndicator? {
      guard isEnabled else { return nil }
      guard let run else {
        return NotchIndicator(leading: [], trailing: [], priority: 10, flash: flashes, flashColor: settings.flashColor)
      }
      return NotchIndicator(
        leading: [run.isPaused ? .symbol("pause.fill") : .progress(run.fractionLeft(at: now))],
        trailing: [.text(TimerRun.clockText(seconds: run.secondsLeft(at: now)))],
        priority: 10,
        flash: flashes,
        flashColor: settings.flashColor
      )
    }
  }

  public enum Action: Equatable, Sendable {
    case start
    case stop
    /// A preset on Home: starts a run of that many minutes.
    case presetTapped(Int)
    case previousPresetTapped
    case nextPresetTapped
    /// Start in the Timer tab: starts the preset it shows.
    case startTapped
    /// The Timer tab became visible: the window opened on it, or the user switched to it.
    case tabShown
    case pauseTapped
    case resumeTapped
    case addFiveMinutesTapped
    case stopTapped
    case tick
    /// The shared run changed: by this feature, or from outside it, such as another Vortex writing the run file or the
    /// file edited or deleted.
    case runChanged
    case flashDue
    case notificationButtonPressed(String)
    case settingsShown
    case soundsLoaded([String])
    case presetsSubmitted(String)
    case soundChosen(String?)
    case flashColorChanged(ColorValue)
    /// Plays the sound and the flashes three seconds later, so the window can be closed first.
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
    case alarm
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
        state.$run.withLock { $0 = nil }
        return .merge(
          saveRun(state),
          .cancel(id: CancelID.tick),
          .cancel(id: CancelID.runChanges),
          .cancel(id: CancelID.buttons),
          .cancel(id: CancelID.alarm),
          .cancel(id: CancelID.test)
        )

      case let .presetTapped(minutes):
        return startRun(minutes: minutes, &state)

      case .previousPresetTapped:
        moveCarousel(by: -1, &state)
        return .none

      case .nextPresetTapped:
        moveCarousel(by: 1, &state)
        return .none

      case .startTapped:
        return startRun(minutes: state.carouselPreset, &state)

      case .tabShown:
        // The tab opens on the preset started last: one browsed and left without starting is forgotten.
        state.chosenPreset = nil
        return .none

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

      case .addFiveMinutesTapped:
        // A whole number of seconds: the ticks stay on the whole seconds of the time left.
        state.now = now
        state.$run.withLock { $0?.add(Self.addedTime) }
        return saveRun(state)

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

      case .flashDue:
        state.flashes += 1
        return .none

      case let .notificationButtonPressed(button):
        // "+5 min" on the notification that time is up: five more minutes, as a new run.
        guard button == Self.addFiveButtonID else { return .none }
        return startRun(minutes: Int(Self.addedTime / 60), remembering: false, &state)

      case .settingsShown:
        return .run { send in await send(.soundsLoaded(await sounds.names())) }

      case let .soundsLoaded(names):
        state.sounds = names
        return .none

      case let .presetsSubmitted(text):
        state.$settings.withLock { $0.presets = TimerSettings.presets(from: text) }
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
        return alarm(state)
      }
    }
    .onChange(of: \.indicator) { _, indicator in
      Reduce { state, _ in
        state.$indicators.withLock { $0[Self.id] = indicator }
        return .none
      }
    }
  }

  /// Starts a run unless one is going: one timer at a time.
  private func startRun(minutes: Int, remembering: Bool = true, _ state: inout State) -> Effect<Action> {
    guard state.isEnabled, state.run == nil else { return .none }
    let now = self.now
    state.now = now
    state.chosenPreset = nil
    state.$run.withLock { $0 = TimerRun.started(minutes: minutes, at: now) }
    if remembering {
      state.$settings.withLock { $0.lastMinutes = minutes }
    }
    return .merge(
      tick(state),
      saveRun(state),
      // The first run asks once whether Vortex may notify; later calls return the saved answer.
      .run { _ in _ = await notifications.requestAuthorization() }
    )
  }

  private func moveCarousel(by step: Int, _ state: inout State) {
    let presets = state.settings.presets
    guard let index = presets.firstIndex(of: state.carouselPreset) else { return }
    state.chosenPreset = presets[min(max(index + step, 0), presets.count - 1)]
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
      alarm(state),
      .run { _ in await notifications.post(Self.doneNotificationID, title, body, [addFive]) }
    )
  }

  /// The sound, and three flashes of the notch 1.5 s apart.
  private func alarm(_ state: State) -> Effect<Action> {
    let sound = state.settings.sound
    return .run { send in
      if let sound { await sounds.play(sound) }
      for flash in 0..<Self.flashesWhenDone {
        if flash > 0 { try await clock.sleep(for: Self.flashInterval) }
        await send(.flashDue)
      }
    }
    .cancellable(id: CancelID.alarm, cancelInFlight: true)
  }

  private func listenToNotificationButtons() -> Effect<Action> {
    .run { send in
      for await button in await notifications.buttonPresses() {
        await send(.notificationButtonPressed(button))
      }
    }
    .cancellable(id: CancelID.buttons, cancelInFlight: true)
  }
}

private let logger = Logger(subsystem: "io.github.ortexisartem.vortex", category: "timer")
