import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// Welcome (S12, S35, S76): a vortex of thin curves converges into the notch, then "Vortex", the text and the button
/// fade in. A dark backdrop in both appearances. With Reduce Motion only the final frame shows.
struct WelcomePage: View {
  let store: StoreOf<OnboardingFeature>
  @Environment(\.reduceMotion) private var reduceMotion
  /// 0: the curves spread out; 1: gathered into the notch.
  @State private var swirl: Double = 0
  @State private var showsTitle = false
  @State private var showsText = false
  @State private var showsButton = false

  var body: some View {
    ZStack(alignment: .top) {
      Color(white: 0.035)
      VortexSwirl(progress: swirl)
        .frame(height: 330)
      VStack(spacing: 0) {
        Spacer(minLength: 0)
        Text(verbatim: "Vortex")
          .font(.system(size: 46, weight: .thin))
          .foregroundStyle(Color.white)
          .opacity(showsTitle ? 1 : 0)
        VStack(spacing: 8) {
          Text("Vortex lives in your notch: a timer, a shelf for files, clipboard history, tasks and keys for Claude.", bundle: .module)
          Text("To make every part work, give it a few permissions. It takes a minute.", bundle: .module)
          Text("On a Mac without a notch, Vortex lives in the menu bar.", bundle: .module)
            .foregroundStyle(Color.white.opacity(0.45))
        }
        .font(.system(size: 13.5))
        .foregroundStyle(Color.white.opacity(0.7))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 64)
        .padding(.top, 14)
        .opacity(showsText ? 1 : 0)
        Button {
          store.send(.getStartedTapped)
        } label: {
          Text("Get started", bundle: .module)
            .foregroundStyle(Color.black)
        }
        .buttonStyle(WelcomeButtonStyle())
        .keyboardShortcut(.defaultAction)
        .padding(.top, 30)
        .padding(.bottom, 56)
        .opacity(showsButton ? 1 : 0)
        .disabled(!showsButton)
      }
    }
    .environment(\.colorScheme, .dark)
    .onAppear(perform: play)
  }

  private func play() {
    guard !reduceMotion else {
      swirl = 1
      showsTitle = true
      showsText = true
      showsButton = true
      return
    }
    withAnimation(.easeInOut(duration: 2.5)) { swirl = 1 }
    withAnimation(.easeOut(duration: 0.6).delay(2.4)) { showsTitle = true }
    withAnimation(.easeOut(duration: 0.6).delay(2.8)) { showsText = true }
    withAnimation(.easeOut(duration: 0.5).delay(3.2)) { showsButton = true }
  }
}

/// The white capsule on the dark backdrop: the page's one main button.
private struct WelcomeButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 14, weight: .semibold))
      .padding(.horizontal, 26)
      .frame(height: 40)
      .background(Capsule().fill(Color.white))
      .opacity(configuration.isPressed ? 0.8 : 1)
      .contentShape(Capsule())
  }
}

/// About 30 thin white curves spiralling in towards the top center, where they gather into the notch's silhouette
/// (S35). Each curve is a shape SwiftUI animates by `progress`, so nothing runs once it settles.
struct VortexSwirl: View {
  var progress: Double
  static let curves = 30

  var body: some View {
    ZStack(alignment: .top) {
      ForEach(0 ..< Self.curves, id: \.self) { index in
        SpiralCurve(index: index, progress: progress)
          .stroke(Color.white.opacity(Self.opacity(index) * (1 - progress * 0.9)), lineWidth: 1)
      }
      // The notch, shown by its edge (S76).
      HangingShape(width: 132, height: 28, cornerRadius: 10, shoulder: 7)
        .fill(Color.black)
        .overlay(
          HangingShape(width: 132, height: 28, cornerRadius: 10, shoulder: 7)
            .stroke(Color.white.opacity(0.55), lineWidth: 1)
        )
        .frame(height: 28)
        .opacity(max(0, (progress - 0.55) / 0.45))
    }
  }

  /// Mixed opacities, the same on every run.
  static func opacity(_ index: Int) -> Double {
    let golden = (Double(index) * 0.618_034).truncatingRemainder(dividingBy: 1)
    return 0.18 + 0.62 * golden
  }
}

/// One curve of the vortex: an arc that winds inwards to the notch at the top center. At `progress` 1 it has
/// shrunk into the notch.
struct SpiralCurve: Shape {
  var index: Int
  var progress: Double

  var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: 14)
    let count = Double(VortexSwirl.curves)
    let share = Double(index) / count
    let jitter = (Double(index) * 0.381_966).truncatingRemainder(dividingBy: 1)
    let outer = Double(max(rect.width, rect.height)) * (0.55 + 0.45 * jitter)
    // The whole vortex turns and tightens as it gathers.
    let squeeze = pow(1 - progress, 1.35)
    let turn = progress * .pi * 1.6
    let start = share * 2 * .pi + turn
    var path = Path()
    let steps = 28
    for step in 0 ... steps {
      let t = Double(step) / Double(steps)
      let angle = start + t * .pi * 1.25
      let radius = outer * (1 - 0.82 * t) * squeeze
      // Flattened below the notch, so the curves pour into it from the sides and below.
      let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + abs(sin(angle)) * radius * 0.62)
      if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    return path
  }
}
