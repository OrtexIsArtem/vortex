import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The frozen screen of a capture: first a frame is drawn on it, then the framed part moves aside and the fields of
/// the new task show next to it. Always dark: it lies over a dimmed screen.
struct CaptureView: View {
  @Bindable var store: StoreOf<CaptureFeature>

  var body: some View {
    let image = store.screenshot.image
    ZStack(alignment: .topLeading) {
      // Blurred behind the fields, so the framed part and the fields stand out.
      Image(decorative: image.cgImage, scale: image.scale)
        .resizable()
        .frame(width: image.size.width, height: image.size.height)
        .blur(radius: store.isFramed ? 14 : 0, opaque: true)
        .animation(.easeOut(duration: 0.3), value: store.isFramed)
      if store.isFramed, let frame = store.frame {
        CaptureDetails(store: store, frame: frame)
      } else {
        Framing(store: store)
      }
      NotchPill(
        notch: store.screenshot.notch,
        screenWidth: image.size.width,
        label: store.isFramed ? Text("New task", bundle: .module) : Text("Freeze frame", bundle: .module)
      )
    }
    .frame(width: image.size.width, height: image.size.height, alignment: .topLeading)
    .environment(\.colorScheme, .dark)
    .ignoresSafeArea()
  }
}

/// Drawing the frame: the screen dims except inside it.
private struct Framing: View {
  let store: StoreOf<CaptureFeature>
  @State private var start: CGPoint?

  var body: some View {
    let size = store.screenshot.image.size
    ZStack(alignment: .topLeading) {
      Path { path in
        path.addRect(CGRect(origin: .zero, size: size))
        if let frame = store.frame { path.addRect(frame) }
      }
      .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))

      if let frame = store.frame {
        FrameOutline(frame: frame)
      }

      // Above the Dock, which shows on the frozen screen too.
      Hint()
        .frame(width: size.width, height: size.height - store.screenshot.bottomInset - 28, alignment: .bottom)
        .allowsHitTesting(false)
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .contentShape(Rectangle())
    .modifier(AreaPointer(kind: .selecting))
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
}

extension Framing {
  /// The rectangle between where the drag began and where the pointer is, whichever way it went.
  static func frame(from start: CGPoint, to end: CGPoint) -> CGRect {
    CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
  }
}

/// The system's pointers, on macOS 15 and later: for selecting an area while the frame is drawn, the usual one once
/// the fields show, the text one over the title.
private struct AreaPointer: ViewModifier {
  enum Kind {
    case selecting
    case usual
    case text
  }

  let kind: Kind

  func body(content: Content) -> some View {
    if #available(macOS 15, *) {
      switch kind {
      case .selecting: content.pointerStyle(.rectSelection)
      case .usual: content.pointerStyle(.default)
      case .text: content.pointerStyle(.horizontalText)
      }
    } else {
      content
    }
  }
}

/// A thin line around the frame, marks at its corners and its size under it.
struct FrameOutline: View {
  let frame: CGRect
  var showsSize = true

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
      if showsSize {
        Text(verbatim: "\(Int(frame.width.rounded())) × \(Int(frame.height.rounded()))")
          .font(.system(size: 11, weight: .medium).monospacedDigit())
          .foregroundStyle(Color.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(Capsule().fill(Color.black.opacity(0.7)))
          .fixedSize()
          .offset(x: frame.minX, y: frame.maxY + 6)
      }
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

/// "Frame an area · Esc to cancel", at the bottom.
private struct Hint: View {
  var body: some View {
    HStack(spacing: 14) {
      Text("Frame an area", bundle: .module)
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
struct NotchPill: View {
  let notch: CGRect?
  let screenWidth: CGFloat
  let label: Text

  var body: some View {
    let ear: CGFloat = 112
    let notch = notch ?? CGRect(x: (screenWidth - 180) / 2, y: 0, width: 180, height: 30)
    let width = notch.width + (ear + 14) * 2
    HStack(spacing: 0) {
      HStack(spacing: 7) {
        Circle()
          .fill(VortexColor.notchText)
          .frame(width: 6, height: 6)
        label
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

/// The framed part on the left, the fields of the task on the right.
private struct CaptureDetails: View {
  @Bindable var store: StoreOf<CaptureFeature>
  let frame: CGRect
  @State private var hasMoved = false
  @FocusState private var isTitleFocused: Bool

  var body: some View {
    let screen = store.screenshot.image.size
    let target = Self.partFrame(for: frame.size, on: screen)
    let shown = hasMoved ? target : frame
    ZStack(alignment: .topLeading) {
      Color.black.opacity(0.55)

      if let part = store.screenshot.image.cropped(to: frame) {
        Image(decorative: part.cgImage, scale: part.scale)
          .resizable()
          .frame(width: shown.width, height: shown.height)
          .clipShape(RoundedRectangle(cornerRadius: hasMoved ? 8 : 0, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: hasMoved ? 8 : 0, style: .continuous)
              .strokeBorder(Color.white.opacity(0.12))
          )
          .shadow(color: .black.opacity(hasMoved ? 0.5 : 0), radius: 30, y: 12)
          .offset(x: shown.minX, y: shown.minY)
      }

      Text("The whole screen is saved too", bundle: .module)
        .font(.system(size: 12))
        .foregroundStyle(Color.white.opacity(0.5))
        .offset(x: target.minX, y: target.maxY + 12)
        .opacity(hasMoved ? 1 : 0)

      fields
        .frame(width: 340)
        .offset(x: target.maxX + 28, y: max(target.midY - 150, 40))
        .opacity(hasMoved ? 1 : 0)
    }
    .frame(width: screen.width, height: screen.height, alignment: .topLeading)
    .modifier(AreaPointer(kind: .usual))
    .onAppear {
      withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { hasMoved = true }
    }
    .task {
      // SwiftUI drops a focus request while the drag that drew the frame winds down: it is asked again on the next
      // frames until the title has the keyboard, with «Задача N» selected.
      for _ in 0..<10 where !isTitleFocused && !Task.isCancelled {
        isTitleFocused = true
        try? await Task.sleep(for: .milliseconds(30))
      }
    }
  }

  /// Where the part settles: in the left half, as large as it was but no larger than that half allows.
  static func partFrame(for size: CGSize, on screen: CGSize) -> CGRect {
    let box = CGSize(width: screen.width * 0.44, height: screen.height * 0.62)
    let scale = min(1, box.width / max(size.width, 1), box.height / max(size.height, 1))
    let fitted = CGSize(width: size.width * scale, height: size.height * scale)
    let left = screen.width * 0.06
    return CGRect(x: left + (box.width - fitted.width) / 2, y: (screen.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
  }

  private var fields: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Name", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
      TextField(text: $store.title.sending(\.titleChanged)) {
        Text("Name", bundle: .module)
      }
      .textFieldStyle(.plain)
      .font(.system(size: 22, weight: .semibold))
      .focused($isTitleFocused)
      .modifier(AreaPointer(kind: .text))
      .onSubmit { store.send(.saveTapped) }
      .padding(.top, 6)

      if let suggestion = store.suggestion, suggestion != store.title {
        HStack(spacing: 8) {
          (Text("From the text: ", bundle: .module) + Text(verbatim: suggestion))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(VortexColor.tertiaryText)
          Spacer(minLength: 4)
          Button {
            store.send(.suggestionTapped)
          } label: {
            Text("Use", bundle: .module)
              .underline()
          }
          .buttonStyle(.plain)
          .foregroundStyle(VortexColor.primaryText)
        }
        .font(.system(size: 12))
        .padding(.top, 8)
      }

      Hairline()
        .padding(.vertical, 14)

      Text("Priority", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
        .padding(.bottom, 8)
      PriorityPicker(selection: Binding(get: { store.priority }, set: { store.send(.priorityChosen($0)) }))

      Hairline()
        .padding(.vertical, 14)

      SourceLine(source: store.source, date: store.capturedAt)

      HStack(spacing: 8) {
        Button {
          store.send(.retakeTapped)
        } label: {
          Image(systemName: "arrow.counterclockwise")
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(VortexColor.secondaryText)
        .help(Text("Frame again", bundle: .module))
        .accessibilityLabel(Text("Frame again", bundle: .module))
        Spacer()
        Button {
          store.send(.cancelTapped)
        } label: {
          Text("Cancel", bundle: .module)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(VortexColor.secondaryText)
        Button {
          store.send(.saveTapped)
        } label: {
          HStack(spacing: 6) {
            Text("Save", bundle: .module)
            Image(systemName: "return")
              .font(.system(size: 10, weight: .semibold))
          }
        }
        .buttonStyle(.primaryCapsule)
      }
      .padding(.top, 16)
    }
    .font(.system(size: 13))
    .foregroundStyle(VortexColor.primaryText)
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color(white: 0.07))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(Color.white.opacity(0.08))
    )
  }
}
