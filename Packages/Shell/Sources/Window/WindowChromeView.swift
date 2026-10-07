import Observation
import SwiftUI
import VortexCore

/// State the window chrome animates: where the window is anchored and whether it is expanded.
@MainActor
@Observable
final class WindowPresentationModel {
  /// The notch the window grows out of; nil when it drops under the menu bar icon.
  var notch: CGSize?
  var isExpanded = false
  @ObservationIgnored var onNotchTapped: () -> Void = {}

  nonisolated init() {}
}

/// The window around the shell's content: morphs out of the notch, or drops under the menu bar icon.
struct WindowChromeView: View {
  let model: WindowPresentationModel
  let content: AnyView
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let size = VortexMetrics.windowSize
    let notch = model.notch
    let isExpanded = model.isExpanded
    let shoulder = notch == nil ? 0 : VortexMetrics.shoulder

    // `content` keeps the same place in the view tree for both placements, so moving between
    // displays never rebuilds a tab or loses its state.
    content
      .frame(width: size.width, height: size.height)
      .environment(\.notchCutout, notch.map { CGRect(x: (size.width - $0.width) / 2, y: 0, width: $0.width, height: $0.height) })
      .environment(\.isWindowOpen, isExpanded)
      .opacity(isExpanded ? 1 : 0)
      .animation(isExpanded ? .easeOut(duration: 0.2).delay(reduceMotion ? 0 : 0.1) : .easeIn(duration: 0.1), value: isExpanded)
      .frame(width: size.width + shoulder * 2, height: size.height, alignment: .top)
      .background(VortexColor.windowBackground)
      .clipShape(WindowShape(progress: reduceMotion || isExpanded ? 1 : 0, notch: notch))
      .overlay {
        if notch == nil {
          RoundedRectangle(cornerRadius: VortexMetrics.menuBarWindowCornerRadius, style: .continuous)
            .strokeBorder(VortexColor.line)
        }
      }
      .overlay(alignment: .top) {
        if let notch {
          // A button rather than a tap gesture: in a window opened by hover, which has no keyboard focus yet, the first
          // click reaches buttons only.
          Button {
            model.onNotchTapped()
          } label: {
            UnevenRoundedRectangle(
              bottomLeadingRadius: VortexMetrics.notchCornerRadius,
              bottomTrailingRadius: VortexMetrics.notchCornerRadius
            )
            .fill(VortexColor.notch)
            .frame(width: notch.width, height: notch.height)
            .contentShape(Rectangle())
          }
          .buttonStyle(NotchButtonStyle())
          // Under the hardware notch a focus ring can't be seen: Tab skips it.
          .focusable(false)
          .accessibilityHidden(true)
        }
      }
      // Out of the notch the shape itself animates; otherwise (and with Reduce Motion) the window fades.
      .scaleEffect(notch == nil && !isExpanded && !reduceMotion ? 0.96 : 1, anchor: .top)
      .opacity(isExpanded || (notch != nil && !reduceMotion) ? 1 : 0)
  }
}

/// The notch stays black while it is pressed.
private struct NotchButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
  }
}

/// The window outline. Out of a notch: a notch-sized tab at progress 0, the full window with concave shoulders
/// at progress 1. Under the menu bar: a rounded rectangle.
struct WindowShape: Shape {
  var progress: CGFloat
  let notch: CGSize?

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func path(in rect: CGRect) -> Path {
    guard let notch else {
      return RoundedRectangle(cornerRadius: VortexMetrics.menuBarWindowCornerRadius, style: .continuous).path(in: rect)
    }
    let full = VortexMetrics.windowSize
    let p = min(max(progress, 0), 1)
    let width = notch.width + (full.width - notch.width) * p
    let height = notch.height + (full.height - notch.height) * p
    let cornerRadius = VortexMetrics.notchCornerRadius
      + (VortexMetrics.windowCornerRadius - VortexMetrics.notchCornerRadius) * p
    return HangingShape(width: width, height: height, cornerRadius: cornerRadius, shoulder: VortexMetrics.shoulder * p)
      .path(in: rect)
  }
}

/// A shape hanging from the top edge, centered horizontally: concave shoulders where it meets the top edge,
/// rounded bottom corners. Used for the window and for the notch with its ears.
struct HangingShape: Shape {
  var width: CGFloat
  var height: CGFloat
  var cornerRadius: CGFloat
  var shoulder: CGFloat

  func path(in rect: CGRect) -> Path {
    let left = rect.midX - width / 2
    let right = rect.midX + width / 2
    let radius = min(cornerRadius, width / 2, height / 2)
    var path = Path()
    path.move(to: CGPoint(x: left - shoulder, y: 0))
    path.addArc(tangent1End: CGPoint(x: left, y: 0), tangent2End: CGPoint(x: left, y: height), radius: shoulder)
    path.addArc(tangent1End: CGPoint(x: left, y: height), tangent2End: CGPoint(x: right, y: height), radius: radius)
    path.addArc(tangent1End: CGPoint(x: right, y: height), tangent2End: CGPoint(x: right, y: 0), radius: radius)
    path.addArc(tangent1End: CGPoint(x: right, y: 0), tangent2End: CGPoint(x: right + shoulder, y: 0), radius: shoulder)
    path.addLine(to: CGPoint(x: right + shoulder, y: 0))
    path.closeSubpath()
    return path
  }
}
