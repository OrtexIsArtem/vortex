import ComposableArchitecture
import SwiftUI
import VortexCore

/// The timer on Home, in the row next to the notch: the drum and its time left of it; «+5» and Start, or pause and stop
/// while a run goes, right of it.
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

  /// Short of room left of the notch, the drum narrows; the time beside it keeps its size.
  private var leading: some View {
    HStack(spacing: 10) {
      DrumRuler(store: store, style: .home)
        .frame(minWidth: 72, maxWidth: 120)
      DrumTime(store: store)
        .fixedSize()
        .frame(minWidth: 46, alignment: .leading)
    }
  }

  private var trailing: some View {
    HStack(spacing: 6) {
      Button {
        store.send(.addFiveMinutesTapped)
      } label: {
        Text(verbatim: "+5")
          .font(.system(size: 13, weight: .medium).monospacedDigit())
          .padding(.horizontal, 12)
          .frame(minWidth: 44, minHeight: 34)
          .background(Capsule().fill(VortexColor.raised))
          .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .foregroundStyle(VortexColor.primaryText)
      .help(Text("Add 5 minutes", bundle: .module))
      .accessibilityLabel(Text("Add 5 minutes", bundle: .module))

      if let run = store.run {
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
      } else {
        Button {
          store.send(.startTapped)
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "play.fill")
              .font(.system(size: 8))
            Text("Start", bundle: .module)
          }
          .font(.system(size: 13, weight: .semibold))
          .padding(.leading, 13)
          .padding(.trailing, 15)
          .frame(minHeight: 34)
          .background(Capsule().fill(VortexColor.accent))
          .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(VortexColor.onAccent)
      }
    }
  }
}

/// The time on the drum, «25 хв», or the time left of the run going, «8:42».
private struct DrumTime: View {
  let store: StoreOf<TimerFeature>

  var body: some View {
    if let run = store.run {
      TickReader(store: store) { now in
        Text(verbatim: TimerRun.clockText(seconds: run.secondsLeft(at: now)))
      }
      .font(.system(size: 15, weight: .medium).monospacedDigit())
      .foregroundStyle(run.isPaused ? VortexColor.secondaryText : VortexColor.primaryText)
    } else {
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(store.settings.minutes, format: .number)
          .font(.system(size: 15, weight: .medium).monospacedDigit())
        Text("min", bundle: .module)
          .font(.system(size: 12))
          .foregroundStyle(VortexColor.secondaryText)
      }
      // The drum says the same to VoiceOver.
      .accessibilityHidden(true)
    }
  }
}
