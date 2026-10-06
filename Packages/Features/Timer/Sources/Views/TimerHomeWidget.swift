import ComposableArchitecture
import SwiftUI
import VortexCore

/// The timer on Home, in the row next to the notch: the presets on both sides of it, or the run going.
struct TimerHomeWidget: View {
  let store: StoreOf<TimerFeature>
  @Environment(\.notchCutout) private var cutout

  /// Space between the groups and the notch.
  static let gap: CGFloat = 12

  var body: some View {
    Group {
      if let cutout {
        HStack(spacing: 0) {
          leading
            .frame(width: max(cutout.minX - Self.gap, 0), alignment: .trailing)
          Color.clear
            .frame(width: cutout.width + Self.gap * 2)
          trailing
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        // Under the menu bar icon there is no notch: one row.
        HStack(spacing: 8) {
          leading
          trailing
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private var leading: some View {
    if let run = store.run {
      HStack(spacing: 10) {
        Text("of \(run.totalMinutes) min", bundle: .module)
          .font(.system(size: 12))
          .foregroundStyle(VortexColor.tertiaryText)
        ProgressRing(fraction: run.fractionLeft(at: store.now))
          .frame(width: 16, height: 16)
      }
    } else {
      HStack(spacing: 6) {
        Image(systemName: "timer")
          .font(.system(size: 13))
          .foregroundStyle(VortexColor.tertiaryText)
          .frame(width: 20)
          .accessibilityHidden(true)
        ForEach(leftPresets, id: \.self) { chip($0) }
      }
    }
  }

  @ViewBuilder
  private var trailing: some View {
    if let run = store.run {
      HStack(spacing: 4) {
        Text(verbatim: TimerRun.clockText(seconds: run.secondsLeft(at: store.now)))
          .font(.system(size: 15, weight: .medium).monospacedDigit())
          .foregroundStyle(run.isPaused ? VortexColor.secondaryText : VortexColor.primaryText)
          .padding(.trailing, 8)
        RoundButton(
          symbol: run.isPaused ? "play.fill" : "pause.fill",
          label: run.isPaused ? Text("Resume", bundle: .module) : Text("Pause", bundle: .module),
          isProminent: true,
          size: 34
        ) {
          store.send(run.isPaused ? .resumeTapped : .pauseTapped)
        }
        RoundButton(symbol: "stop.fill", label: Text("Stop", bundle: .module), size: 34) {
          store.send(.stopTapped)
        }
        Button {
          store.send(.addFiveMinutesTapped)
        } label: {
          Text("+5 min", bundle: .module)
            .font(.system(size: 12.5, weight: .medium).monospacedDigit())
            .padding(.horizontal, 8)
            .frame(height: 34)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(VortexColor.secondaryText)
      }
    } else {
      HStack(spacing: 6) {
        ForEach(rightPresets, id: \.self) { chip($0) }
      }
    }
  }

  /// Half of the presets left of the notch, the rest right of it.
  private var leftPresets: [Int] {
    Array(store.settings.presets.prefix(store.settings.presets.count / 2))
  }

  private var rightPresets: [Int] {
    Array(store.settings.presets.dropFirst(store.settings.presets.count / 2))
  }

  private func chip(_ minutes: Int) -> some View {
    PresetChip(minutes: minutes, isMarked: minutes == store.settings.lastMinutes) {
      store.send(.presetTapped(minutes))
    }
  }
}

/// A preset that starts the timer in one click; the one started last is filled and has ▶.
private struct PresetChip: View {
  let minutes: Int
  let isMarked: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        if isMarked {
          Image(systemName: "play.fill")
            .font(.system(size: 8))
        }
        Text(minutes, format: .number)
      }
      .font(.system(size: 13, weight: isMarked ? .semibold : .medium).monospacedDigit())
      .padding(.horizontal, 12)
      .frame(minWidth: 44, minHeight: 34)
      .background(Capsule().fill(isMarked ? VortexColor.accent : VortexColor.raised))
      .foregroundStyle(isMarked ? VortexColor.onAccent : VortexColor.primaryText)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("Timer for \(minutes) minutes", bundle: .module))
  }
}
