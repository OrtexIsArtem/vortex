import AppKit
import Observation
import SwiftUI
import VortexCore

/// What the closed notch shows: the notch size and the ears around it.
@MainActor
@Observable
final class EarsModel {
  var notchSize: CGSize = .zero
  var earWidth: CGFloat = 0
  var ears = NotchEars()

  nonisolated init() {}
}

/// The closed notch with the indicators of features on both sides of the cutout.
struct NotchEarsView: View {
  let model: EarsModel

  var body: some View {
    let hasEars = model.earWidth > 0
    let shoulder = hasEars ? VortexMetrics.shoulder : 0
    let size = CGSize(width: model.notchSize.width + model.earWidth * 2, height: model.notchSize.height)
    HStack(spacing: 0) {
      EarItems(items: model.ears.left)
        .frame(width: model.earWidth)
      Color.clear
        .frame(width: model.notchSize.width)
      EarItems(items: model.ears.right)
        .frame(width: model.earWidth)
    }
    .frame(height: model.notchSize.height)
    .padding(.horizontal, shoulder)
    .background(
      NotchWindowShape(progress: 1, notch: size, full: size, shoulder: shoulder, cornerRadius: hasEars ? 14 : 10)
        .fill(VortexColor.notch)
    )
    .environment(\.colorScheme, .dark)
    .accessibilityHidden(true)
  }
}

private struct EarItems: View {
  let items: [NotchIndicator.Item]

  var body: some View {
    HStack(spacing: EarsMetrics.spacing) {
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        switch item {
        case let .symbol(name):
          Image(systemName: name)
            .font(.system(size: 13, weight: .medium))
            .frame(width: EarsMetrics.iconWidth)
        case let .text(text):
          Text(verbatim: text)
            .font(.system(size: 13, weight: .medium).monospacedDigit())
        case let .progress(value):
          ProgressRing(value: value)
            .frame(width: EarsMetrics.iconWidth, height: EarsMetrics.iconWidth)
        }
      }
    }
    .foregroundStyle(VortexColor.notchText)
    .lineLimit(1)
  }
}

private struct ProgressRing: View {
  let value: Double

  var body: some View {
    ZStack {
      Circle().stroke(VortexColor.notchTrack, lineWidth: 2)
      Circle()
        .trim(from: 0, to: min(max(value, 0), 1))
        .stroke(VortexColor.notchText, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .padding(1)
  }
}

/// Widths of the ears, measured with the same font the view uses, so the panel fits them exactly.
enum EarsMetrics {
  static let padding: CGFloat = 14
  static let spacing: CGFloat = 6
  static let iconWidth: CGFloat = 16

  static func width(of items: [NotchIndicator.Item]) -> CGFloat {
    guard !items.isEmpty else { return 0 }
    let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    let widths = items.map { item -> CGFloat in
      switch item {
      case .symbol, .progress:
        iconWidth
      case let .text(text):
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
      }
    }
    return widths.reduce(0, +) + spacing * CGFloat(items.count - 1)
  }

  /// Both ears get the same width, so the cutout stays centered.
  static func earWidth(for ears: NotchEars) -> CGFloat {
    guard !ears.isEmpty else { return 0 }
    return max(width(of: ears.left), width(of: ears.right)) + padding * 2
  }
}
