import ComposableArchitecture
import SwiftUI
import VortexCore

/// The timer on Home, in the row next to the notch: the drum and its time left of it; «+5», «+10» and Start, or pause
/// and stop while a run goes, right of it.
struct TimerHomeWidget: View {
  let store: StoreOf<TimerFeature>
  @Environment(\.notchCutout) private var cutout
  @Environment(\.isWindowOpen) private var isWindowOpen
  /// The drum stands at five minutes whenever Home shows, whatever was set on it before.
  @State private var minutes = TimerFeature.defaultMinutes

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
    // Set back as the window opens, while the content is still faded out: as it closes, the jump would show.
    .onChange(of: isWindowOpen) { _, isOpen in
      if isOpen { setDrumBack() }
    }
    // Set back when any run starts, also one from the notification's «+5 min», so the drum shows 5 once it is over.
    .onChange(of: store.run == nil) { _, isIdle in
      if !isIdle { setDrumBack() }
    }
  }

  /// Short of room left of the notch, the drum narrows; the time beside it keeps its size.
  private var leading: some View {
    HStack(spacing: 10) {
      DrumRuler(store: store, minutes: $minutes, style: .home)
        .frame(minWidth: 72, maxWidth: 120)
      DrumTime(store: store, minutes: minutes)
        .fixedSize()
        .frame(minWidth: 46, alignment: .leading)
    }
  }

  private var trailing: some View {
    HStack(spacing: 6) {
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
        addButton(5, label: Text("Add 5 minutes", bundle: .module))
        addButton(10, label: Text("Add 10 minutes", bundle: .module))
        Button {
          store.send(.startTapped(minutes: minutes))
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "play.fill")
              .font(.system(size: 8))
            Text("Start", bundle: .module)
          }
        }
        .buttonStyle(PrimaryCapsuleButtonStyle(height: 34, fontSize: 13))
      }
    }
  }

  /// Turns the drum on by `added` minutes, up to its end.
  private func addButton(_ added: Int, label: Text) -> some View {
    Button {
      minutes = TimerFeature.clampedMinutes(minutes + added)
    } label: {
      Text(verbatim: "+\(added)")
        .monospacedDigit()
    }
    .buttonStyle(QuietCapsuleButtonStyle(height: 34, fontSize: 13))
    .help(label)
    .accessibilityLabel(label)
  }

  /// Back to five minutes, without the drum turning there: the window is opening, or a run started.
  private func setDrumBack() {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) { minutes = TimerFeature.defaultMinutes }
  }
}

/// The time on the drum, «5 min», or the time left of the run going, «8:42».
private struct DrumTime: View {
  let store: StoreOf<TimerFeature>
  let minutes: Int

  var body: some View {
    if let run = store.run {
      TickReader(store: store) { now in
        Text(verbatim: TimerRun.clockText(seconds: run.secondsLeft(at: now)))
      }
      .font(.system(size: 15, weight: .medium).monospacedDigit())
      .foregroundStyle(run.isPaused ? VortexColor.secondaryText : VortexColor.primaryText)
    } else {
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(minutes, format: .number)
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
