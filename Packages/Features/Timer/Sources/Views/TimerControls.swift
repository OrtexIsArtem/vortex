import ComposableArchitecture
import SwiftUI
import VortexCore

/// Hands its content the date to show the run at. While the window is open, that is the store's `now`, which moves at
/// every tick. While it is closed, the content is invisible and gets the current date once: the store's `now` is not
/// read, so Observation does not track it and the hidden view does not re-render at every tick. The current date
/// rather than a constant one, since the content still fades out for a moment after the window closes and must not
/// jump to another time meanwhile. Keep it around the views that show the time, not around a whole tab.
struct TickReader<Content: View>: View {
  let store: StoreOf<TimerFeature>
  @ViewBuilder let content: (Date) -> Content
  @Environment(\.isWindowOpen) private var isWindowOpen

  var body: some View {
    content(isWindowOpen ? store.now : Date.now)
  }
}

/// A round control: filled for the main one (pause or resume), bare for the others.
struct RoundButton: View {
  let symbol: String
  let label: Text
  var isProminent = false
  var size: CGFloat = VortexMetrics.hitTarget
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .semibold))
        .frame(width: size, height: size)
        .background(Circle().fill(isProminent ? VortexColor.raised : .clear))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(isProminent ? VortexColor.primaryText : VortexColor.secondaryText)
    .help(label)
    .accessibilityLabel(label)
  }
}

/// The time left as a ring, like the one in the closed notch.
struct ProgressRing: View {
  let fraction: Double

  var body: some View {
    ZStack {
      Circle().stroke(VortexColor.track, lineWidth: 2)
      Circle()
        .trim(from: 0, to: min(max(fraction, 0), 1))
        .stroke(VortexColor.primaryText, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .padding(1)
    .accessibilityHidden(true)
  }
}
