import Observation
import SwiftUI
import VortexCore

/// The glow around the closed notch when an indicator asks for a flash, see `NotchIndicator.flash`.
@MainActor
@Observable
final class GlowModel {
  /// The whole glow, larger than the notch so it spreads past its edges.
  var size: CGSize = .zero
  /// The notch with its ears, which the glow hugs.
  var silhouette: CGSize = .zero
  var cornerRadius: CGFloat = 0
  var shoulder: CGFloat = 0
  var color = ColorValue.white
  /// Grows by one for every flash.
  var trigger = 0

  nonisolated init() {}
}

/// How far the glow reaches beyond the notch and its ears.
enum GlowMetrics {
  static let spread: CGFloat = 130
  static let depth: CGFloat = 100
}

/// A soft gradient falling from the notch, and a halo hugging its outline; blinks twice, then fades.
struct NotchGlowView: View {
  let model: GlowModel

  var body: some View {
    let color = model.color.color
    let size = model.size
    ZStack(alignment: .top) {
      // A half circle as wide as the glow, squashed into a half ellipse as deep as it.
      RadialGradient(
        colors: [color.opacity(0.95), color.opacity(0.45), color.opacity(0)],
        center: .top,
        startRadius: 0,
        endRadius: max(size.width / 2, 1)
      )
      .frame(width: size.width, height: max(size.width / 2, 1))
      .scaleEffect(x: 1, y: size.height / max(size.width / 2, 1), anchor: .top)
      .frame(width: size.width, height: size.height, alignment: .top)
      HangingShape(
        width: model.silhouette.width,
        height: model.silhouette.height,
        cornerRadius: model.cornerRadius,
        shoulder: model.shoulder
      )
      .fill(color)
      .blur(radius: 8)
    }
    .frame(width: size.width, height: size.height, alignment: .top)
    .keyframeAnimator(initialValue: 0.0, trigger: model.trigger) { content, intensity in
      content.opacity(intensity)
    } keyframes: { _ in
      CubicKeyframe(1, duration: 0.16)
      CubicKeyframe(0.35, duration: 0.28)
      CubicKeyframe(1, duration: 0.16)
      CubicKeyframe(0, duration: 0.9)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
