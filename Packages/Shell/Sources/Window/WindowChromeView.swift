import Observation
import SwiftUI
import VortexCore

/// State the window chrome animates: where the window is anchored, its size and whether it is expanded.
@MainActor
@Observable
final class WindowPresentationModel {
  /// Where the notch the window grows out of cuts into the content (the window without its shoulders), in the
  /// content's coordinates; nil when the window drops under the menu bar icon.
  var notch: CGRect?
  var isExpanded = false
  /// The size the content is laid out at.
  var size: WindowSize = .regular
  /// The width the window is drawn at, its shoulders not counted. It follows `size` with an animation, while the
  /// content already has its new size.
  var shownWidth: CGFloat = WindowSize.regular.size.width
  @ObservationIgnored var onNotchTapped: () -> Void = {}

  nonisolated init() {}
}

/// The window around the shell's content: morphs out of the notch, or drops under the menu bar icon.
struct WindowChromeView: View {
  let model: WindowPresentationModel
  let content: AnyView
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let size = model.size.size
    let notch = model.notch
    let isExpanded = model.isExpanded
    let shoulder = notch == nil ? 0 : VortexMetrics.shoulder

    // `content` keeps the same place in the view tree for both placements, so moving between
    // displays never rebuilds a tab or loses its state. It is laid out from the window's left edge, which stays put
    // as the window grows right.
    content
      .frame(width: size.width, height: size.height)
      .environment(\.notchCutout, notch)
      .environment(\.isWindowOpen, isExpanded)
      .opacity(isExpanded ? 1 : 0)
      .animation(isExpanded ? .easeOut(duration: 0.2).delay(reduceMotion ? 0 : 0.1) : .easeIn(duration: 0.1), value: isExpanded)
      .padding(.leading, shoulder)
      // The window as drawn: as wide as `shownWidth`, which catches up with a new size.
      .frame(width: model.shownWidth + shoulder * 2, height: size.height, alignment: .topLeading)
      .background(VortexColor.windowBackground)
      .clipShape(WindowShape(progress: reduceMotion || isExpanded ? 1 : 0, notch: notch))
      .overlay {
        if notch == nil {
          RoundedRectangle(cornerRadius: VortexMetrics.menuBarWindowCornerRadius, style: .continuous)
            .strokeBorder(VortexColor.line)
        }
      }
      .overlay(alignment: .topLeading) {
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
          .padding(.leading, shoulder + notch.minX)
        }
      }
      // Out of the notch the shape itself animates; otherwise (and with Reduce Motion) the window fades.
      .scaleEffect(notch == nil && !isExpanded && !reduceMotion ? 0.96 : 1, anchor: .top)
      .opacity(isExpanded || (notch != nil && !reduceMotion) ? 1 : 0)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

/// The notch stays black while it is pressed.
private struct NotchButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
  }
}

/// The window outline, in a rect as wide as the window with its shoulders. Out of a notch: the notch at progress 0,
/// where `notch` cuts into the content, and the full window with concave shoulders at progress 1. Under the menu bar:
/// a rounded rectangle.
struct WindowShape: Shape {
  var progress: CGFloat
  let notch: CGRect?

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func path(in rect: CGRect) -> Path {
    guard let notch else {
      return RoundedRectangle(cornerRadius: VortexMetrics.menuBarWindowCornerRadius, style: .continuous).path(in: rect)
    }
    let shoulder = VortexMetrics.shoulder
    let p = min(max(progress, 0), 1)
    let notchLeft = rect.minX + shoulder + notch.minX
    let left = notchLeft + (rect.minX + shoulder - notchLeft) * p
    let right = notchLeft + notch.width + (rect.maxX - shoulder - notchLeft - notch.width) * p
    let height = notch.height + (rect.height - notch.height) * p
    let cornerRadius = VortexMetrics.notchCornerRadius
      + (VortexMetrics.windowCornerRadius - VortexMetrics.notchCornerRadius) * p
    return HangingShape(width: right - left, height: height, cornerRadius: cornerRadius, shoulder: shoulder * p, left: left)
      .path(in: rect)
  }
}

/// A shape hanging from the top edge, centered horizontally unless `left` places it: concave shoulders where it meets
/// the top edge, rounded bottom corners. Used for the window and for the notch with its ears.
struct HangingShape: Shape {
  var width: CGFloat
  var height: CGFloat
  var cornerRadius: CGFloat
  var shoulder: CGFloat
  /// Where its left edge is, without the shoulder; nil centers it.
  var left: CGFloat?

  func path(in rect: CGRect) -> Path {
    let left = left ?? rect.midX - width / 2
    let right = left + width
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
