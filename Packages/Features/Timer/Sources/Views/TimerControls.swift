import SwiftUI
import VortexCore

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
