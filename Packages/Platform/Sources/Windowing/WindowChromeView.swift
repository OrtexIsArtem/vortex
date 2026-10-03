import Observation
import SwiftUI
import VortexCore

/// State the window chrome animates: where the window is anchored and whether it is expanded.
@MainActor
@Observable
final class WindowPresentationModel {
  enum Mode: Equatable {
    /// Grows out of a notch of this size.
    case notch(CGSize)
    /// Drops down under the menu bar icon.
    case menuBar
  }

  var mode: Mode = .menuBar
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
    switch model.mode {
    case let .notch(notch):
      notchChrome(notch: notch)
    case .menuBar:
      menuBarChrome
    }
  }

  private func notchChrome(notch: CGSize) -> some View {
    let size = VortexMetrics.windowSize
    let shoulder = VortexMetrics.shoulder
    let shape = NotchWindowShape(
      progress: reduceMotion || model.isExpanded ? 1 : 0,
      notch: notch,
      full: size,
      shoulder: shoulder,
      cornerRadius: VortexMetrics.windowCornerRadius
    )
    return ZStack(alignment: .top) {
      ZStack(alignment: .top) {
        VortexColor.windowBackground
        content
          .frame(width: size.width, height: size.height)
          .environment(\.notchCutout, CGRect(x: (size.width - notch.width) / 2, y: 0, width: notch.width, height: notch.height))
          .opacity(model.isExpanded ? 1 : 0)
          .animation(contentAnimation, value: model.isExpanded)
      }
      .frame(width: size.width + shoulder * 2, height: size.height, alignment: .top)
      .clipShape(shape)

      NotchCapShape()
        .fill(VortexColor.notch)
        .frame(width: notch.width, height: notch.height)
        .contentShape(Rectangle())
        .onTapGesture { model.onNotchTapped() }
        .accessibilityHidden(true)
    }
    .frame(width: size.width + shoulder * 2, height: size.height, alignment: .top)
    .opacity(reduceMotion && !model.isExpanded ? 0 : 1)
  }

  private var menuBarChrome: some View {
    let size = VortexMetrics.windowSize
    let shape = RoundedRectangle(cornerRadius: VortexMetrics.menuBarWindowCornerRadius, style: .continuous)
    return content
      .frame(width: size.width, height: size.height)
      .background(VortexColor.windowBackground)
      .clipShape(shape)
      .overlay(shape.strokeBorder(VortexColor.line))
      .scaleEffect(reduceMotion || model.isExpanded ? 1 : 0.96, anchor: .top)
      .opacity(model.isExpanded ? 1 : 0)
  }

  private var contentAnimation: Animation {
    model.isExpanded ? .easeOut(duration: 0.2).delay(reduceMotion ? 0 : 0.1) : .easeIn(duration: 0.1)
  }
}

/// The window outline: a notch-sized tab at progress 0, the full window with concave shoulders at progress 1.
struct NotchWindowShape: Shape {
  var progress: CGFloat
  let notch: CGSize
  let full: CGSize
  let shoulder: CGFloat
  let cornerRadius: CGFloat

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let p = min(max(progress, 0), 1)
    let width = notch.width + (full.width - notch.width) * p
    let height = notch.height + (full.height - notch.height) * p
    let radius = min(10 + (cornerRadius - 10) * p, height / 2, width / 2)
    let s = shoulder * p
    let k: CGFloat = 0.5523
    let left = rect.midX - width / 2
    let right = rect.midX + width / 2

    var path = Path()
    path.move(to: CGPoint(x: left - s, y: 0))
    path.addCurve(
      to: CGPoint(x: left, y: s),
      control1: CGPoint(x: left - s + s * k, y: 0),
      control2: CGPoint(x: left, y: s - s * k)
    )
    path.addLine(to: CGPoint(x: left, y: height - radius))
    path.addCurve(
      to: CGPoint(x: left + radius, y: height),
      control1: CGPoint(x: left, y: height - radius + radius * k),
      control2: CGPoint(x: left + radius - radius * k, y: height)
    )
    path.addLine(to: CGPoint(x: right - radius, y: height))
    path.addCurve(
      to: CGPoint(x: right, y: height - radius),
      control1: CGPoint(x: right - radius + radius * k, y: height),
      control2: CGPoint(x: right, y: height - radius + radius * k)
    )
    path.addLine(to: CGPoint(x: right, y: s))
    path.addCurve(
      to: CGPoint(x: right + s, y: 0),
      control1: CGPoint(x: right, y: s - s * k),
      control2: CGPoint(x: right + s - s * k, y: 0)
    )
    path.closeSubpath()
    return path
  }
}

/// The hardware notch: square top, rounded bottom corners.
struct NotchCapShape: Shape {
  func path(in rect: CGRect) -> Path {
    let radius = min(10, rect.height / 2)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
    path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
    path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}
