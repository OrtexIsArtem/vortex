import SwiftUI
import VortexCore
import VortexPlatform

/// A task marked done in the list: its row crumples into a paper ball at the done mark, and the ball flies off into
/// «Done». Only a picture over the list; the task has already left it.
struct DoneFlight: Identifiable, Equatable {
  let id = UUID()
  let task: TaskItem
  /// The row, in the tab's coordinate space.
  let row: CGRect
  /// Where the ball lands: the middle of «Done».
  let target: CGPoint

  static let coordinateSpace = "tasks"
  /// From the click to the landing.
  static let duration: Duration = .milliseconds(820)
  /// How long the row crumples in its place before the task leaves the list, so the rows below close up only while
  /// the ball flies.
  static let crumple: Duration = .milliseconds(280)
  /// The done mark's middle, from the row's leading edge: the row crumples towards it.
  static let markInset: CGFloat = 25
}

/// The flights under way, drawn over the whole tab; they take no clicks.
struct DoneFlights: View {
  let flights: [DoneFlight]
  let landed: (DoneFlight) -> Void

  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(flights) { flight in
        DoneFlightView(flight: flight) { landed(flight) }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// What changes along a flight: first the row is crushed while the ball grows out of it, then the ball travels.
private struct FlightFrame {
  var rowScaleX = 1.0
  var rowScaleY = 1.0
  var rowTurn = 0.0
  var rowOpacity = 1.0
  var ballScale = 0.25
  var ballOpacity = 0.0
  var spin = 0.0
  /// 0 at the done mark, 1 at «Done».
  var travel = 0.0
  /// How far above the straight line the ball is, in points: the arc of the throw.
  var lift = 0.0
}

private struct DoneFlightView: View {
  let flight: DoneFlight
  let onLanded: () -> Void
  @State private var isThrown = false

  var body: some View {
    let row = flight.row
    let start = CGPoint(x: row.minX + DoneFlight.markInset, y: row.midY)
    let anchor = UnitPoint(x: DoneFlight.markInset / max(row.width, 1), y: 0.5)
    KeyframeAnimator(initialValue: FlightFrame(), trigger: isThrown) { frame in
      ZStack(alignment: .topLeading) {
        RowFace(task: flight.task)
          .frame(width: row.width, height: row.height)
          .scaleEffect(x: frame.rowScaleX, y: frame.rowScaleY, anchor: anchor)
          .rotationEffect(.degrees(frame.rowTurn), anchor: anchor)
          .opacity(frame.rowOpacity)
          .position(x: row.midX, y: row.midY)
        PaperBall(seed: flight.id.hashValue)
          .frame(width: 22, height: 22)
          .rotationEffect(.degrees(frame.spin))
          .scaleEffect(frame.ballScale)
          .opacity(frame.ballOpacity)
          .position(
            x: start.x + (flight.target.x - start.x) * frame.travel,
            y: start.y + (flight.target.y - start.y) * frame.travel - frame.lift
          )
      }
    } keyframes: { _ in
      // The row is crushed towards the done mark in three squeezes, twisting one way and back, like paper in a fist.
      KeyframeTrack(\.rowScaleX) {
        CubicKeyframe(0.68, duration: 0.08)
        CubicKeyframe(0.36, duration: 0.08)
        CubicKeyframe(0.08, duration: 0.12)
      }
      KeyframeTrack(\.rowScaleY) {
        CubicKeyframe(0.78, duration: 0.08)
        CubicKeyframe(0.52, duration: 0.08)
        CubicKeyframe(0.26, duration: 0.12)
      }
      KeyframeTrack(\.rowTurn) {
        CubicKeyframe(-6, duration: 0.08)
        CubicKeyframe(7, duration: 0.08)
        CubicKeyframe(-12, duration: 0.12)
      }
      KeyframeTrack(\.rowOpacity) {
        LinearKeyframe(1, duration: 0.16)
        LinearKeyframe(0, duration: 0.12)
      }
      // The ball takes the row's place with a small bounce, then shrinks on the way.
      KeyframeTrack(\.ballScale) {
        LinearKeyframe(0.25, duration: 0.12)
        SpringKeyframe(1, duration: 0.2, spring: .bouncy)
        CubicKeyframe(0.4, duration: 0.48)
      }
      KeyframeTrack(\.ballOpacity) {
        LinearKeyframe(0, duration: 0.12)
        LinearKeyframe(1, duration: 0.08)
        LinearKeyframe(1, duration: 0.47)
        LinearKeyframe(0, duration: 0.13)
      }
      KeyframeTrack(\.spin) {
        LinearKeyframe(0, duration: 0.12)
        CubicKeyframe(600, duration: 0.68)
      }
      // Thrown once it is a ball: along an arc up and over into «Done».
      KeyframeTrack(\.travel) {
        LinearKeyframe(0, duration: 0.3)
        CubicKeyframe(1, duration: 0.5)
      }
      KeyframeTrack(\.lift) {
        LinearKeyframe(0, duration: 0.3)
        CubicKeyframe(34, duration: 0.24)
        CubicKeyframe(0, duration: 0.26)
      }
    }
    .task {
      isThrown = true
      try? await Task.sleep(for: DoneFlight.duration)
      onLanded()
    }
  }
}

/// The row as it looked when it was marked: the checked mark, the picture and the title.
private struct RowFace: View {
  let task: TaskItem

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle().fill(VortexColor.accent)
        Image(systemName: "checkmark")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(VortexColor.onAccent)
      }
      .frame(width: 18, height: 18)
      .frame(width: 30, height: 30)
      FileThumbnail(url: task.cropURL, size: CGSize(width: 64, height: 44)) {
        VortexColor.thumbnail
      }
      .frame(width: 64, height: 44)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      Text(verbatim: task.displayTitle)
        .font(.system(size: 13, weight: .medium))
        .lineLimit(1)
        .foregroundStyle(VortexColor.primaryText)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(VortexColor.raised))
  }
}

/// A crumpled sheet: a lumpy round outline with a few creases, light as paper in either theme.
private struct PaperBall: View {
  let seed: Int

  var body: some View {
    let outline = PaperOutline(seed: seed)
    outline
      .fill(Color(white: 0.93))
      .overlay(PaperCreases(seed: seed).stroke(Color.black.opacity(0.22), lineWidth: 0.8))
      .overlay(outline.stroke(Color.black.opacity(0.18), lineWidth: 0.6))
      .shadow(color: .black.opacity(0.3), radius: 3, y: 1.5)
  }
}

/// Points round a circle at radii that wander, the same for one seed.
private struct PaperOutline: Shape {
  let seed: Int

  func path(in rect: CGRect) -> Path {
    var random = SeededRandom(seed)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = min(rect.width, rect.height) / 2
    let corners = 11
    var path = Path()
    for index in 0..<corners {
      let angle = Double(index) / Double(corners) * 2 * .pi
      let reach = radius * (0.8 + 0.2 * random.next())
      let point = CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach)
      if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
  }
}

/// Short zigzags inside the ball.
private struct PaperCreases: Shape {
  let seed: Int

  func path(in rect: CGRect) -> Path {
    var random = SeededRandom(seed &+ 7)
    var path = Path()
    for _ in 0..<3 {
      var point = CGPoint(x: rect.minX + rect.width * (0.25 + 0.5 * random.next()), y: rect.minY + rect.height * (0.25 + 0.5 * random.next()))
      path.move(to: point)
      for _ in 0..<2 {
        point.x += rect.width * (random.next() - 0.5) * 0.45
        point.y += rect.height * (random.next() - 0.5) * 0.45
        path.addLine(to: point)
      }
    }
    return path
  }
}

/// Numbers in 0..<1 that come out the same for one seed, so a ball keeps its shape while it flies.
private struct SeededRandom {
  private var state: UInt64

  init(_ seed: Int) {
    state = UInt64(bitPattern: Int64(seed)) | 1
  }

  mutating func next() -> Double {
    state = state &* 6364136223846793005 &+ 1442695040888963407
    return Double(state >> 11) / Double(1 << 53)
  }
}
