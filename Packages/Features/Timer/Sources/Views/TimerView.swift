import ComposableArchitecture
import SwiftUI
import VortexCore

/// The Timer tab: ‹ 25 min › and Start; while a run is going, the time left in large digits and its controls.
public struct TimerView: View {
  let store: StoreOf<TimerFeature>
  @Environment(\.isWindowOpen) private var isWindowOpen
  @FocusState private var isFocused: Bool

  public init(store: StoreOf<TimerFeature>) {
    self.store = store
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Timer", bundle: .module)
        .font(.system(size: 13, weight: .semibold))
        .frame(height: VortexMetrics.headerHeight)
        .padding(.leading, 10)

      Group {
        if let run = store.run {
          RunningTimer(run: run, now: store.now) { store.send($0) }
        } else {
          PresetCarousel(minutes: store.carouselPreset, presets: store.settings.presets) { store.send($0) }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      // Centered in the window rather than in the space under the header.
      .padding(.bottom, VortexMetrics.headerHeight)
    }
    .focusable()
    .focusEffectDisabled()
    .focused($isFocused)
    .onKeyPress(.leftArrow) { carousel(.previousPresetTapped) }
    .onKeyPress(.rightArrow) { carousel(.nextPresetTapped) }
    .onKeyPress(.return) { carousel(.startTapped) }
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
  }

  /// The carousel keys work only before a run starts.
  private func carousel(_ action: TimerFeature.Action) -> KeyPress.Result {
    guard store.run == nil else { return .ignored }
    store.send(action)
    return .handled
  }
}

/// ‹ 25 min › and Start.
private struct PresetCarousel: View {
  let minutes: Int
  let presets: [Int]
  let send: @MainActor (TimerFeature.Action) -> Void

  var body: some View {
    VStack(spacing: 22) {
      HStack(spacing: 14) {
        ArrowButton(symbol: "chevron.left", label: Text("Shorter", bundle: .module)) {
          send(.previousPresetTapped)
        }
        .disabled(minutes == presets.first)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(minutes, format: .number)
            .font(.system(size: 76, weight: .thin).monospacedDigit())
            .contentTransition(.numericText())
          Text("min", bundle: .module)
            .font(.system(size: 15))
            .foregroundStyle(VortexColor.secondaryText)
        }
        .frame(minWidth: 170)
        .animation(.snappy(duration: 0.2), value: minutes)
        ArrowButton(symbol: "chevron.right", label: Text("Longer", bundle: .module)) {
          send(.nextPresetTapped)
        }
        .disabled(minutes == presets.last)
      }
      Button {
        send(.startTapped)
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
}

private struct ArrowButton: View {
  let symbol: String
  let label: Text
  let action: () -> Void
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .medium))
        .frame(width: VortexMetrics.hitTarget, height: VortexMetrics.hitTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(isEnabled ? VortexColor.secondaryText : VortexColor.track)
    .help(label)
    .accessibilityLabel(label)
  }
}

/// The time left, when it ends, how much is left as a line, and the controls.
private struct RunningTimer: View {
  let run: TimerRun
  let now: Date
  let send: @MainActor (TimerFeature.Action) -> Void

  var body: some View {
    let secondsLeft = run.secondsLeft(at: now)
    VStack(spacing: 0) {
      Text(verbatim: TimerRun.clockText(seconds: secondsLeft))
        .font(.system(size: 76, weight: .thin).monospacedDigit())
        .foregroundStyle(run.isPaused ? VortexColor.secondaryText : VortexColor.primaryText)
        .contentTransition(.numericText(countsDown: true))
        .animation(.snappy(duration: 0.25), value: secondsLeft)
      caption
        .font(.system(size: 12.5))
        .foregroundStyle(VortexColor.tertiaryText)
        .padding(.top, 2)
      ProgressLine(fraction: run.fractionLeft(at: now))
        .frame(width: 260, height: 2)
        .padding(.top, 20)
      HStack(spacing: 10) {
        RoundButton(
          symbol: run.isPaused ? "play.fill" : "pause.fill",
          label: run.isPaused ? Text("Resume", bundle: .module) : Text("Pause", bundle: .module),
          isProminent: true
        ) {
          send(run.isPaused ? .resumeTapped : .pauseTapped)
        }
        RoundButton(symbol: "stop.fill", label: Text("Stop", bundle: .module)) {
          send(.stopTapped)
        }
        Button {
          send(.addFiveMinutesTapped)
        } label: {
          Text("+5 min", bundle: .module)
        }
        .buttonStyle(.quietCapsule)
      }
      .padding(.top, 22)
    }
  }

  /// "of 25 min · until 14:57"; paused, "Paused · of 25 min".
  private var caption: Text {
    let total = Text("of \(run.totalMinutes) min", bundle: .module)
    guard case let .running(endsAt) = run.phase else {
      return Text("Paused", bundle: .module) + Text(verbatim: " · ") + total
    }
    return total + Text(verbatim: " · ") + Text("until \(endsAt, format: .dateTime.hour().minute())", bundle: .module)
  }
}

/// A thin line: the time left out of the total.
private struct ProgressLine: View {
  let fraction: Double

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule().fill(VortexColor.track)
        Capsule()
          .fill(VortexColor.primaryText)
          .frame(width: geometry.size.width * min(max(fraction, 0), 1))
      }
    }
    .accessibilityHidden(true)
  }
}
