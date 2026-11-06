import AppKit
import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// What the window shows instead of the sidebar and the tab while the keys are locked for cleaning: the keyboard drawn
/// on top, below the notch, each key as washed as the user's presses made it; the title and subtitle bottom left, and
/// the button that turns the keyboard back on bottom right.
struct KeyboardCleaningView: View {
  let store: StoreOf<KeyboardCleaningFeature>
  @Environment(\.notchCutout) private var notchCutout

  /// Around the board and the bottom row; the board is as wide as the window allows.
  static let margin: CGFloat = 28
  private static let metrics = KeyboardBoard.Metrics(width: VortexMetrics.windowSize.width - 2 * margin)
  /// Laid out once: ISO's for an ISO keyboard, ANSI's for the others.
  private static let ansi = KeyboardBoard(.ansi, metrics: metrics)
  private static let iso = KeyboardBoard(.iso, metrics: metrics)

  /// Touch ID's tooltip, and VoiceOver's hint on the title, which the hidden drawing can't give.
  static let touchIDWarning = Text(
    "Don't press Touch ID: it locks your Mac, and Vortex can't block it.",
    bundle: .module
  )

  var body: some View {
    VStack(alignment: .leading, spacing: 32) {
      KeyboardBoardView(board: store.layout == .iso ? Self.iso : Self.ansi, presses: store.presses)
        // Decoration: VoiceOver reads the title, the subtitle and the button.
        .accessibilityHidden(true)
      HStack(spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Keyboard cleaning mode", bundle: .module)
            .font(.system(size: 17, weight: .semibold))
          Text("All keys are locked", bundle: .module)
            .font(.system(size: 13))
            .foregroundStyle(VortexColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Self.touchIDWarning)
        Spacer(minLength: 0)
        Button {
          store.send(.stopTapped)
        } label: {
          Text("Turn the keyboard back on", bundle: .module)
        }
        .buttonStyle(PrimaryCapsuleButtonStyle(height: 44, fontSize: 14))
      }
    }
    .padding(.horizontal, Self.margin)
    // Centered in what the notch leaves, so nothing sits under it.
    .padding(.top, notchCutout?.maxY ?? 0)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(VortexColor.windowBackground)
  }
}

/// The board with its keys, each as washed as its `presses` made it.
private struct KeyboardBoardView: View {
  let board: KeyboardBoard
  let presses: [KeyboardKey: Int]
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let palette = colorScheme == .dark ? KeyPalette.dark : KeyPalette.light
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(palette.board)
        .overlay {
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(palette.boardEdge)
        }
      ForEach(board.caps) { cap in
        let count = cap.key.flatMap { presses[$0] } ?? 0
        KeyCapView(cap: cap, presses: count, washes: KeyboardCleaningFeature.washes(after: count), palette: palette)
          // Only a key whose presses changed draws again.
          .equatable()
          .frame(width: cap.frame.width, height: cap.frame.height)
          .offset(x: cap.frame.minX, y: cap.frame.minY)
      }
    }
    .frame(width: board.size.width, height: board.size.height, alignment: .topLeading)
  }
}

/// One key: as clean as `washes` says, nudged down a point by each of its `presses`.
private struct KeyCapView: View, Equatable {
  let cap: KeyboardBoard.Cap
  let presses: Int
  let washes: Int
  let palette: KeyPalette
  @Environment(\.reduceMotion) private var reduceMotion
  @State private var isPressed = false

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.cap == rhs.cap && lhs.presses == rhs.presses && lhs.washes == rhs.washes && lhs.palette == rhs.palette
  }

  var body: some View {
    let shape = KeyCapShape(cap.shape)
    if cap.shape == .touchID {
      touchID(shape)
    } else {
      let isClean = washes == KeyboardCleaningFeature.cleanest
      shape.fill(palette.fill(washes))
        .overlay { shape.stroke(palette.edge(washes), lineWidth: 2).clipShape(shape) }
        .overlay(alignment: label.alignment) {
          Text(verbatim: cap.label)
            .font(.system(size: cap.isShort ? 9 : 10))
            .foregroundStyle(isClean ? VortexColor.primaryText : VortexColor.secondaryText)
            .lineLimit(1)
            .frame(width: label.width)
            .padding(.bottom, label.alignment == .center ? 0 : cap.isShort ? 3 : 5)
        }
        .background { shape.fill(palette.shadow).offset(y: 1) }
        .opacity(palette.opacity(washes))
        .offset(y: isPressed ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: washes)
        .task(id: presses) {
          // A press, even of a key washed clean already: down a point, back up after a moment.
          guard presses > 0, !reduceMotion else { return }
          withAnimation(.easeOut(duration: 0.06)) { isPressed = true }
          try? await Task.sleep(for: .milliseconds(140))
          guard !Task.isCancelled else { return }
          withAnimation(.easeOut(duration: 0.12)) { isPressed = false }
        }
    }
  }

  /// Labels sit low on the key, as on the website: ISO's Return in its lower part, and the half-height arrows in their
  /// middle.
  private var label: (alignment: Alignment, width: CGFloat?) {
    if case let .tallReturn(lowerWidth, _) = cap.shape { return (.bottomTrailing, lowerWidth) }
    return (cap.frame.height < 24 && !cap.isShort ? .center : .bottom, nil)
  }

  /// Never washed and never locked: ringed like a key that is still live, with a mark that says not to press it.
  private func touchID(_ shape: KeyCapShape) -> some View {
    shape.fill(palette.touchID)
      .overlay { shape.stroke(palette.edge(KeyboardCleaningFeature.cleanest), lineWidth: 2).clipShape(shape) }
      .overlay {
        Image(systemName: "exclamationmark")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(VortexColor.secondaryText)
      }
      .background { shape.fill(palette.shadow).offset(y: 1) }
      .contentShape(shape)
      .help(KeyboardCleaningView.touchIDWarning)
  }
}

/// A key's outline in its own frame.
private struct KeyCapShape: Shape {
  let kind: KeyboardBoard.Cap.Shape

  init(_ kind: KeyboardBoard.Cap.Shape) {
    self.kind = kind
  }

  func path(in rect: CGRect) -> Path {
    switch kind {
    case .key:
      return Path(roundedRect: rect, cornerRadius: min(6, rect.height / 3), style: .continuous)
    case .touchID:
      // The website's `border-radius: 50% / 70%`, as CSS scales it to fit: an oval with straight top and bottom.
      return Path(roundedRect: rect, cornerSize: CGSize(width: rect.width * 0.357, height: rect.height / 2))
    case let .tallReturn(lowerWidth, upperHeight):
      // An upside-down L: the full width over `upperHeight`, then only the right `lowerWidth` down to the bottom. Each
      // corner is rounded, the inner one too.
      let inner = CGPoint(x: rect.maxX - lowerWidth, y: rect.minY + upperHeight)
      let corners = [
        CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY),
        CGPoint(x: inner.x, y: rect.maxY), inner, CGPoint(x: rect.minX, y: inner.y),
      ]
      var path = Path()
      path.move(to: CGPoint(x: rect.minX, y: rect.minY + 6))
      for (index, corner) in corners.enumerated() {
        path.addArc(tangent1End: corner, tangent2End: corners[(index + 1) % corners.count], radius: 6)
      }
      path.closeSubpath()
      return path
    }
  }
}

/// The board's monochrome colors, from the website's dark keyboard: a dirty key is its dim locked key, a clean one its
/// bright live key; the light theme mirrors them. Made once per theme, with each wash level's colors worked out.
private struct KeyPalette: Equatable {
  static let dark = KeyPalette(
    board: 0x141416, boardEdge: .white.opacity(0.05), touchID: 0x18181B, shadow: .black.opacity(0.6),
    fill: (0x1F1F23, 0x3A3A40), edge: (.white, 0.05, 0.35), dirtyOpacity: 0.22
  )
  static let light = KeyPalette(
    board: 0xEBEBEE, boardEdge: .black.opacity(0.05), touchID: 0xF7F7F9, shadow: .black.opacity(0.12),
    fill: (0xF4F4F6, 0xFFFFFF), edge: (.black, 0.04, 0.2), dirtyOpacity: 0.35
  )

  /// How far each wash level is from dirty to clean: the first press takes off the most, so each one shows.
  private static let steps: [CGFloat] = [0, 0.4, 0.7, 1]

  let board: Color
  let boardEdge: Color
  let touchID: Color
  let shadow: Color
  private let fills: [Color]
  private let edges: [Color]
  private let opacities: [CGFloat]

  private init(
    board: UInt32, boardEdge: Color, touchID: UInt32, shadow: Color,
    fill: (dirty: UInt32, clean: UInt32), edge: (color: Color, dirty: CGFloat, clean: CGFloat), dirtyOpacity: CGFloat
  ) {
    self.board = Color(nsColor: NSColor(hex: board))
    self.boardEdge = boardEdge
    self.touchID = Color(nsColor: NSColor(hex: touchID))
    self.shadow = shadow
    let dirty = NSColor(hex: fill.dirty)
    let clean = NSColor(hex: fill.clean)
    fills = Self.steps.map { Color(nsColor: dirty.blended(withFraction: $0, of: clean) ?? clean) }
    edges = Self.steps.map { edge.color.opacity(edge.dirty + (edge.clean - edge.dirty) * $0) }
    opacities = Self.steps.map { dirtyOpacity + (1 - dirtyOpacity) * $0 }
  }

  private func index(_ level: Int) -> Int {
    max(0, min(level, Self.steps.count - 1))
  }

  func fill(_ level: Int) -> Color { fills[index(level)] }
  func edge(_ level: Int) -> Color { edges[index(level)] }
  func opacity(_ level: Int) -> CGFloat { opacities[index(level)] }
}

private extension NSColor {
  convenience init(hex: UInt32) {
    self.init(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}
