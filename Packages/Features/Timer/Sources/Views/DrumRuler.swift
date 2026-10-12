import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The time picker: a ruler wrapped around a drum under a fixed mark, a tick per minute and a longer one every five.
/// Towards the edges the ticks crowd, shrink and fade as the drum turns away. Scroll it, drag it or click a tick. While a
/// run goes it shows the time left, turning towards zero, and takes no input.
struct DrumRuler: View {
  let store: StoreOf<TimerFeature>
  /// The minutes to start. The view that shows the drum keeps them, and sets them back when it goes away.
  @Binding var minutes: Int
  let style: DrumStyle
  @State private var scroll = ScrollSteps()
  @State private var drag: DragStart?

  var body: some View {
    Group {
      if let run = store.run {
        TickReader(store: store) { now in
          DrumTicks(value: run.remaining(at: now) / 60, last: Int((run.total / 60).rounded(.up)), style: style)
        }
        .accessibilityHidden(true)
      } else {
        DrumTicks(value: Double(minutes), last: TimerFeature.minuteRange.upperBound, style: style)
          .animation(.snappy(duration: 0.2), value: minutes)
          .overlay {
            GeometryReader { proxy in
              ScrollDragArea(help: String(localized: "Scroll, drag or click a tick", bundle: .module)) {
                handle($0, width: proxy.size.width)
              }
            }
          }
          .accessibilityElement()
          .accessibilityLabel(Text("Timer length", bundle: .module))
          .accessibilityValue(Text("\(minutes) min", bundle: .module))
          .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: turn(to: minutes + 1)
            case .decrement: turn(to: minutes - 1)
            @unknown default: break
            }
          }
      }
    }
    .frame(height: style.height)
    .background {
      // A faint sheen where the drum faces the viewer.
      EllipticalGradient(colors: [VortexColor.primaryText.opacity(0.06), .clear], startRadiusFraction: 0, endRadiusFraction: 0.5)
        .accessibilityHidden(true)
    }
    .overlay(alignment: .top) {
      Capsule()
        .fill(VortexColor.primaryText)
        .frame(width: 2, height: style.markHeight)
        .padding(.top, style.markTop)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
  }

  /// The minutes are read at each event: several can come before the view is drawn again.
  private func handle(_ event: ScrollDragEvent, width: CGFloat) {
    // Events already on their way when a run starts find the drum showing the time left.
    guard store.run == nil else { return }
    let minutes = self.minutes
    switch event {
    case let .scrolled(delta):
      let steps = scroll.minutes(for: delta, points: style.scrollPoints)
      if steps != 0 { turn(to: minutes + steps) }
    case let .pressed(point):
      drag = DragStart(point: point, minutes: minutes)
    case let .dragged(point):
      guard var start = drag else { return }
      if !start.moved, hypot(point.x - start.point.x, point.y - start.point.y) > 2 {
        start.moved = true
        drag = start
      }
      // The drum follows the pointer: dragging to the left brings later minutes under the mark.
      if start.moved {
        turn(to: start.minutes + Int(((start.point.x - point.x) / style.spacing).rounded()))
      }
    case let .released(point):
      defer { drag = nil }
      guard let start = drag, !start.moved else { return }
      // A click turns the tick under the pointer to the mark.
      let drum = DrumGeometry(width: width, spacing: style.spacing)
      turn(to: drum.minute(atX: point.x, value: Double(start.minutes)))
    }
  }

  /// Sets only a change, within the drum's range: a drag reports the same minute many times.
  private func turn(to value: Int) {
    let value = TimerFeature.clampedMinutes(value)
    if value != minutes { minutes = value }
  }
}

private struct DragStart {
  let point: CGPoint
  let minutes: Int
  /// Past a couple of points either way the press is a drag; otherwise it ends as a click.
  var moved = false
}

/// The drum's sizes: small next to the notch on Home, large with numbers in the Timer tab.
struct DrumStyle {
  /// Between ticks under the mark; a drag turns the drum a minute per this many points, so it follows the pointer.
  var spacing: CGFloat
  /// Two fingers on the trackpad turn it a minute per this many points: well over `spacing`, as macOS counts more
  /// points the quicker the fingers go, so a small swipe turns it a few minutes rather than flying past them.
  var scrollPoints: CGFloat
  var height: CGFloat
  var minorTick: CGFloat
  var majorTick: CGFloat
  /// Where the ticks stand under the mark; round the drum they shrink towards `middle`, as things further away do.
  var baseline: CGFloat
  var middle: CGFloat
  var markTop: CGFloat
  var markHeight: CGFloat
  var showsNumbers: Bool

  static let home = DrumStyle(
    spacing: 6, scrollPoints: 16, height: 34, minorTick: 7, majorTick: 12, baseline: 25, middle: 17, markTop: 4, markHeight: 23,
    showsNumbers: false
  )
  static let tab = DrumStyle(
    spacing: 9, scrollPoints: 23, height: 56, minorTick: 9, majorTick: 16, baseline: 32, middle: 22, markTop: 4, markHeight: 32,
    showsNumbers: true
  )
}

/// A ruler wrapped around a drum seen from the front: under the mark the ticks stand `spacing` apart, towards the edges
/// they crowd as the drum turns away.
struct DrumGeometry {
  let width: CGFloat
  let spacing: CGFloat

  /// Ticks further round than this, in radians, are too crowded to draw.
  static let edgeAngle = 1.48

  var radius: CGFloat { width / 2 }

  /// How far the drum turns per minute, in radians.
  var anglePerMinute: Double { radius > 0 ? spacing / radius : 0 }

  /// How many minutes show on each side of the mark.
  var reach: Int { anglePerMinute > 0 ? Int((Self.edgeAngle / anglePerMinute).rounded(.up)) : 0 }

  /// Where `minute` shows while `value` is under the mark: its x, and how squarely it faces the viewer, 1 under the
  /// mark and 0 at the edge. nil round the back.
  func spot(of minute: Double, value: Double) -> (x: CGFloat, facing: Double)? {
    let angle = (minute - value) * anglePerMinute
    guard anglePerMinute > 0, abs(angle) <= Self.edgeAngle else { return nil }
    return (radius + radius * sin(angle), cos(angle))
  }

  /// The minute shown at `x`, to the nearest whole one, while `value` is under the mark.
  func minute(atX x: CGFloat, value: Double) -> Int {
    guard anglePerMinute > 0 else { return Int(value.rounded()) }
    let sine = min(max((x - radius) / radius, -0.99), 0.99)
    return Int((value + asin(sine) / anglePerMinute).rounded())
  }
}

/// Turns scrolls into whole minutes. The drum moves with the fingers, so a swipe to the left or up brings later minutes
/// under the mark. A mouse wheel turns it a minute per notch; a trackpad, a minute per `points`, and a quarter as far
/// once the fingers lift and it coasts: macOS coasts a quick swipe two or three times as far as the fingers went, so
/// the coast, not the fingers, would carry most of it. What is left over towards the next minute is dropped when the
/// fingers touch down again or turn back, so every swipe starts afresh.
struct ScrollSteps {
  /// Points towards the next minute; positive adds time.
  private var remainder: CGFloat = 0

  mutating func minutes(for delta: ScrollDelta, points: CGFloat) -> Int {
    let push = -(abs(delta.x) > abs(delta.y) ? delta.x : delta.y) * (delta.isMomentum ? 0.25 : 1)
    guard delta.isPrecise else {
      remainder = 0
      return push > 0 ? 1 : push < 0 ? -1 : 0
    }
    if delta.beginsGesture || (push != 0 && remainder != 0 && (push > 0) != (remainder > 0)) {
      remainder = 0
    }
    remainder += push
    let steps = (remainder / points).rounded(.towardZero)
    remainder -= steps * points
    return Int(steps)
  }
}

/// The ticks, and in the Timer tab their numbers, drawn for `value` under the mark. Animatable, so the drum turns
/// smoothly from one minute to the next.
private struct DrumTicks: View, Animatable {
  var value: Double
  /// The last minute with a tick: the drum's end, or the total of the run going.
  let last: Int
  let style: DrumStyle

  // SwiftUI interpolates it off the main actor's view updates; a Double is safe to hand over.
  nonisolated var animatableData: Double {
    get { value }
    set { value = newValue }
  }

  var body: some View {
    Canvas { context, size in
      let drum = DrumGeometry(width: size.width, spacing: style.spacing)
      let under = Int(value.rounded(.down))
      let unlitMajor = VortexColor.primaryText.opacity(0.32)
      let unlitMinor = VortexColor.primaryText.opacity(0.18)
      let first = max(0, under - drum.reach)
      let last = max(first, min(self.last, under + drum.reach))
      for minute in first...last {
        guard let spot = drum.spot(of: Double(minute), value: value) else { continue }
        let nearness = 0.6 + 0.4 * spot.facing
        let isMajor = minute % 5 == 0
        let isLit = Double(minute) <= value + 0.0001
        let height = (isMajor ? style.majorTick : style.minorTick) * nearness
        let bottom = style.middle + (style.baseline - style.middle) * nearness
        let width = 0.8 + 0.7 * spot.facing
        let color = isMajor
          ? (isLit ? VortexColor.primaryText : unlitMajor)
          : (isLit ? VortexColor.secondaryText : unlitMinor)
        context.opacity = 0.15 + 0.85 * spot.facing * spot.facing
        context.fill(
          Path(roundedRect: CGRect(x: spot.x - width / 2, y: bottom - height, width: width, height: height), cornerRadius: width / 2),
          with: .color(color)
        )
        if style.showsNumbers, isMajor, spot.facing > 0.35 {
          // One size, so the text layout is cached; the fading says how far round the drum the number is.
          let number = Text(verbatim: String(minute))
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(isLit ? VortexColor.secondaryText : VortexColor.tertiaryText)
          context.draw(number, at: CGPoint(x: spot.x, y: bottom + 5), anchor: .top)
        }
      }
    }
    .mask {
      LinearGradient(
        stops: [
          .init(color: .clear, location: 0),
          .init(color: .black, location: 0.16),
          .init(color: .black, location: 0.84),
          .init(color: .clear, location: 1),
        ],
        startPoint: .leading,
        endPoint: .trailing
      )
    }
    .accessibilityHidden(true)
  }
}
