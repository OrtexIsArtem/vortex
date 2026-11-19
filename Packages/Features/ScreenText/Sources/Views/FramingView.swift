import AppKit
import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The frozen screen of a capture: the user drags a frame over it, and once they let go the frame stays while its
/// text is read. Outside the frame the screen dims. In the look of Tasks' framing, which lives in its own module; this
/// is a lean copy of its own. Always dark: it lies over a dimmed screen.
struct FramingView: View {
  let store: StoreOf<ScreenTextFeature>

  var body: some View {
    if let capture = store.capture {
      let image = capture.screenshot.image
      ZStack(alignment: .topLeading) {
        Image(decorative: image.cgImage, scale: image.scale)
          .resizable()
          .frame(width: image.size.width, height: image.size.height)
        FrameArea(store: store, capture: capture, isReading: store.phase.isReading)
        NotchPill(notch: capture.screenshot.notch, screenWidth: image.size.width)
      }
      .frame(width: image.size.width, height: image.size.height, alignment: .topLeading)
      .environment(\.colorScheme, .dark)
      .ignoresSafeArea()
    }
  }
}

/// Drawing the frame: the screen dims except inside it, the pointer is a crosshair, and the hint says what to do.
private struct FrameArea: View {
  let store: StoreOf<ScreenTextFeature>
  let capture: ScreenTextFeature.Capture
  let isReading: Bool
  @State private var start: CGPoint?

  var body: some View {
    let size = capture.screenshot.image.size
    ZStack(alignment: .topLeading) {
      Path { path in
        path.addRect(CGRect(origin: .zero, size: size))
        if let frame = capture.frame { path.addRect(frame.standardized) }
      }
      .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))

      if let frame = capture.frame {
        FrameOutline(frame: frame.standardized)
      }

      // Above the Dock, which shows on the frozen screen too.
      Hint(isReading: isReading)
        .frame(width: size.width, height: size.height - capture.screenshot.bottomInset - 28, alignment: .bottom)
        .allowsHitTesting(false)
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .contentShape(Rectangle())
    .modifier(Crosshair())
    .gesture(
      DragGesture(minimumDistance: 0, coordinateSpace: .local)
        .onChanged { value in
          let start = start ?? value.startLocation
          self.start = start
          store.send(.frameChanged(Self.frame(from: start, to: value.location)))
        }
        .onEnded { value in
          let start = start ?? value.startLocation
          self.start = nil
          store.send(.frameEnded(Self.frame(from: start, to: value.location)))
        }
    )
  }

  /// The rectangle between where the drag began and where the pointer is, whichever way it went.
  static func frame(from start: CGPoint, to end: CGPoint) -> CGRect {
    CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
  }
}

/// The crosshair pointer over the frozen screen: the system's pointer for selecting an area on macOS 15 and later,
/// the crosshair cursor before. The overlay sets the arrow back as it closes.
private struct Crosshair: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 15, *) {
      content.pointerStyle(.rectSelection)
    } else {
      content.onContinuousHover { phase in
        if case .active = phase { NSCursor.crosshair.set() }
      }
    }
  }
}

/// A thin line around the frame and marks at its corners.
private struct FrameOutline: View {
  let frame: CGRect

  var body: some View {
    ZStack(alignment: .topLeading) {
      Rectangle()
        .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
      CornerMarks()
        .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .square))
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
    }
    .allowsHitTesting(false)
  }
}

/// Short strokes along each corner.
private struct CornerMarks: Shape {
  func path(in rect: CGRect) -> Path {
    let length = min(12, rect.width / 3, rect.height / 3)
    var path = Path()
    for (corner, dx, dy) in [
      (CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
      (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
      (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
      (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0),
    ] {
      path.move(to: CGPoint(x: corner.x + dx * length, y: corner.y))
      path.addLine(to: corner)
      path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * length))
    }
    return path
  }
}

/// "Frame the text · Esc to cancel" at the bottom; "Reading the text…" once the mouse is let go.
private struct Hint: View {
  let isReading: Bool

  var body: some View {
    HStack(spacing: 14) {
      Group {
        if isReading {
          Text("Reading the text…", bundle: .module)
        } else {
          Text("Frame the text", bundle: .module)
        }
      }
      .foregroundStyle(Color.white)
      Text("Esc to cancel", bundle: .module)
        .foregroundStyle(Color.white.opacity(0.55))
    }
    .font(.system(size: 12.5, weight: .medium))
    .padding(.horizontal, 16)
    .frame(height: 34)
    .background(Capsule().fill(Color.black.opacity(0.75)))
    .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
  }
}

/// The notch, grown a little to the sides like its ears: what is going on, and that Esc leaves.
private struct NotchPill: View {
  let notch: CGRect?
  let screenWidth: CGFloat

  var body: some View {
    let ear: CGFloat = 112
    let notch = notch ?? CGRect(x: (screenWidth - 180) / 2, y: 0, width: 180, height: 30)
    let width = notch.width + (ear + 14) * 2
    HStack(spacing: 0) {
      HStack(spacing: 7) {
        Circle()
          .fill(VortexColor.notchText)
          .frame(width: 6, height: 6)
        // Which feature froze the screen: Tasks' says "Freeze frame".
        Text(ScreenTextModule.title)
          .lineLimit(1)
      }
      .frame(width: ear, alignment: .leading)
      .padding(.leading, 14)
      Spacer(minLength: notch.width)
      Text(verbatim: "Esc")
        .foregroundStyle(VortexColor.notchText.opacity(0.55))
        .frame(width: ear, alignment: .trailing)
        .padding(.trailing, 14)
    }
    .font(.system(size: 11.5, weight: .medium))
    .foregroundStyle(VortexColor.notchText)
    .frame(width: width, height: notch.height)
    // Rounded like the ears of the closed notch.
    .background(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14).fill(VortexColor.notch))
    .offset(x: notch.midX - width / 2, y: 0)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
