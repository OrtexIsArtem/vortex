import SwiftUI
import VortexCore
import VortexPlatform

/// A task's whole screen over the display: the framed part stays as it was, the rest dims and an outline closes in on
/// the part, so the eye finds it at once. Only drawn over the picture, so it costs nothing to save. Always dark, like
/// the capture; a click anywhere closes it.
struct TaskScreenView: View {
  let image: ScreenImage
  /// The framed part, in fractions of the screen; nil for tasks saved before it was kept, which show the screen alone.
  let area: CGRect?
  let number: Int
  let onClose: () -> Void
  @Environment(\.notchCutout) private var notch
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isShown = false
  @State private var isMarked = false
  /// Clicks close it from a moment after it shows, so the second click of a double click on the picture does not.
  @State private var takesClicks = false

  var body: some View {
    GeometryReader { proxy in
      let bounds = CGRect(origin: .zero, size: proxy.size)
      let picture = Self.fitted(image.size, in: bounds)
      ZStack(alignment: .topLeading) {
        // Around a screen of other proportions than this display's.
        Color.black
        Image(decorative: image.cgImage, scale: image.scale)
          .resizable()
          .frame(width: picture.width, height: picture.height)
          .offset(x: picture.minX, y: picture.minY)
        if let area {
          let part = CGRect(
            x: picture.minX + area.minX * picture.width,
            y: picture.minY + area.minY * picture.height,
            width: area.width * picture.width,
            height: area.height * picture.height
          )
          Path { path in
            path.addRect(bounds)
            path.addRect(part)
          }
          // As dim as the screen was while the frame was drawn.
          .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
          .opacity(isMarked ? 1 : 0)
          FrameOutline(frame: isMarked || reduceMotion ? part : part.insetBy(dx: -24, dy: -24), showsSize: false)
            .opacity(isMarked ? 1 : 0)
        }
        NotchPill(notch: notch, screenWidth: proxy.size.width, label: Text(verbatim: TaskItem.defaultTitle(number: number)))
      }
      .opacity(isShown ? 1 : 0)
    }
    .ignoresSafeArea()
    .environment(\.colorScheme, .dark)
    .contentShape(Rectangle())
    .onTapGesture {
      if takesClicks { onClose() }
    }
    .task {
      try? await Task.sleep(for: .milliseconds(350))
      takesClicks = true
    }
    .onAppear {
      withAnimation(.easeOut(duration: 0.15)) { isShown = true }
      withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.86).delay(0.1)) {
        isMarked = true
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("The whole screen", bundle: .module))
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { onClose() }
  }

  /// `size` scaled to fit in `bounds`, in its middle.
  static func fitted(_ size: CGSize, in bounds: CGRect) -> CGRect {
    let scale = min(bounds.width / max(size.width, 1), bounds.height / max(size.height, 1))
    let fitted = CGSize(width: size.width * scale, height: size.height * scale)
    return CGRect(
      x: bounds.midX - fitted.width / 2,
      y: bounds.midY - fitted.height / 2,
      width: fitted.width,
      height: fitted.height
    )
  }
}
