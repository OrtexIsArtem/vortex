import ComposableArchitecture
import SwiftUI
import VortexCore

/// The Timer tab: the minutes in large digits, the drum under them and Start, then the quick starts; while a run goes,
/// the time left, when it ends, the drum turning towards zero, and pause and stop.
public struct TimerView: View {
  let store: StoreOf<TimerFeature>
  @Environment(\.isWindowOpen) private var isWindowOpen
  @FocusState private var isFocused: Bool
  /// The drum stands at five minutes whenever the tab shows, whatever was set on it before.
  @State private var minutes = TimerFeature.defaultMinutes

  public init(store: StoreOf<TimerFeature>) {
    self.store = store
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Timer", bundle: .module)
        .font(.system(size: 13, weight: .semibold))
        .frame(height: VortexMetrics.headerHeight)
        .padding(.leading, 10)

      VStack(spacing: 0) {
        Group {
          if let run = store.run {
            RunningTime(run: run, store: store)
          } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text(minutes, format: .number)
                .font(.system(size: 76, weight: .thin).monospacedDigit())
              Text("min", bundle: .module)
                .font(.system(size: 15))
                .foregroundStyle(VortexColor.secondaryText)
            }
            // The drum says the same to VoiceOver.
            .accessibilityHidden(true)
          }
        }
        .frame(height: 76)
        caption
          .font(.system(size: 12.5))
          .foregroundStyle(VortexColor.tertiaryText)
          .frame(height: 18)
          .padding(.top, 6)
        DrumRuler(store: store, minutes: $minutes, style: .tab)
          .frame(width: 360)
          .padding(.top, 10)
        controls
          .padding(.top, 18)
        quickStarts
          .padding(.top, 12)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      // Centered in the window rather than in the space under the header.
      .padding(.bottom, VortexMetrics.headerHeight)
    }
    .focusable()
    .focusEffectDisabled()
    .focused($isFocused)
    .onKeyPress(.leftArrow) { turn(by: -1) }
    .onKeyPress(.rightArrow) { turn(by: 1) }
    .onKeyPress(.return) {
      guard store.run == nil else { return .ignored }
      start(minutes)
      return .handled
    }
    // Only the press toggles, so a held key toggles once. Its repeats are taken without doing anything: left alone, each
    // would reach the end of the responder chain, where AppKit beeps.
    .onKeyPress(.space, phases: .down) { _ in
      guard let run = store.run else { return .ignored }
      store.send(run.isPaused ? .resumeTapped : .pauseTapped)
      return .handled
    }
    .onKeyPress(.space, phases: .repeat) { _ in store.run == nil ? .ignored : .handled }
    .task(id: isWindowOpen) {
      if isWindowOpen { isFocused = true }
    }
    // Set back as the window opens, while the content is still faded out: as it closes, the jump would show.
    .onChange(of: isWindowOpen) { _, isOpen in
      if isOpen { setDrumBack() }
    }
    // Set back when any run starts, also one from the notification's «+5 min», so the drum shows 5 once it is over.
    .onChange(of: store.run == nil) { _, isIdle in
      if !isIdle { setDrumBack() }
    }
  }

  /// ← → turn the drum a minute before a run starts.
  private func turn(by step: Int) -> KeyPress.Result {
    guard store.run == nil else { return .ignored }
    minutes = TimerFeature.clampedMinutes(minutes + step)
    return .handled
  }

  private func start(_ minutes: Int) {
    store.send(.startTapped(minutes: minutes))
  }

  /// Back to five minutes, without the drum turning there: the window is opening, or a run started.
  private func setDrumBack() {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) { minutes = TimerFeature.defaultMinutes }
  }

  /// "of 25 min · until 14:57"; paused, "Paused · of 25 min"; nothing before a run starts.
  @ViewBuilder
  private var caption: some View {
    if let run = store.run {
      let total = Text("of \(run.totalMinutes) min", bundle: .module)
      if case let .running(endsAt) = run.phase {
        total + Text(verbatim: " · ") + Text("until \(endsAt, format: .dateTime.hour().minute())", bundle: .module)
      } else {
        Text("Paused", bundle: .module) + Text(verbatim: " · ") + total
      }
    } else {
      Color.clear
    }
  }

  /// Start for the drum's minutes; while a run goes, pause and stop.
  private var controls: some View {
    HStack(spacing: 10) {
      if let run = store.run {
        RoundButton(
          symbol: run.isPaused ? "play.fill" : "pause.fill",
          label: run.isPaused ? Text("Resume", bundle: .module) : Text("Pause", bundle: .module),
          isProminent: true
        ) {
          store.send(run.isPaused ? .resumeTapped : .pauseTapped)
        }
        RoundButton(symbol: "stop.fill", label: Text("Stop", bundle: .module)) {
          store.send(.stopTapped)
        }
      } else {
        Button {
          start(minutes)
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "play.fill")
              .font(.system(size: 9))
            Text("Start", bundle: .module)
          }
        }
        .buttonStyle(.primaryCapsule)
      }
    }
    .frame(height: VortexMetrics.hitTarget)
  }

  /// One click starts a run of that many minutes. Hidden while a run goes, but its room is kept, so nothing moves.
  private var quickStarts: some View {
    HStack(spacing: 6) {
      ForEach(TimerFeature.quickStarts, id: \.self) { quick in
        Button {
          start(quick)
        } label: {
          Text(quick, format: .number)
            .monospacedDigit()
            .frame(minWidth: 16)
        }
        .buttonStyle(.quietCapsule)
        .help(Text("Start a \(quick)-minute timer", bundle: .module))
        .accessibilityLabel(Text("Start a \(quick)-minute timer", bundle: .module))
      }
    }
    .opacity(store.run == nil ? 1 : 0)
    .disabled(store.run != nil)
    .accessibilityHidden(store.run != nil)
  }
}

/// The time left in large digits; paused, dimmed. No digit animation: it would run every second for the whole run, and
/// costs a lot of CPU even unseen.
private struct RunningTime: View {
  let run: TimerRun
  let store: StoreOf<TimerFeature>

  var body: some View {
    TickReader(store: store) { now in
      Text(verbatim: TimerRun.clockText(seconds: run.secondsLeft(at: now)))
    }
    .font(.system(size: 76, weight: .thin).monospacedDigit())
    .foregroundStyle(run.isPaused ? VortexColor.secondaryText : VortexColor.primaryText)
  }
}
