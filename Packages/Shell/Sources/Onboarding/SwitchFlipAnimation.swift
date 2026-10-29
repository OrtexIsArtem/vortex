import AppKit
import QuartzCore
import SwiftUI
import VortexCore

/// The illustration's moving parts: the pointer goes to Vortex's switch and the switch turns on, every ~3 s (S36).
///
/// They are Core Animation layers with one repeating explicit animation each. The render server plays it, so Vortex
/// does no work for it, during the moves or between them: an animation SwiftUI drives costs the app a frame of work
/// every display refresh while it runs. Placed over the static switch the mock draws, `switchFrame` in this view's
/// coordinates, which are SwiftUI's: the origin at the top left.
struct SwitchFlipAnimation: NSViewRepresentable {
  var switchFrame: CGRect
  var scale: CGFloat

  func makeNSView(context: Context) -> SwitchFlipView {
    SwitchFlipView()
  }

  func updateNSView(_ view: SwitchFlipView, context: Context) {
    view.place(switchFrame: switchFrame, scale: scale)
  }
}

final class SwitchFlipView: NSView {
  /// One move: the pointer comes, the switch turns on and stays a while, the pointer goes, the switch is off again.
  static let cycle: CFTimeInterval = 3.4

  private let track = CALayer()
  private let knob = CALayer()
  private let pointer = CALayer()
  private var switchFrame = CGRect.zero
  private var scale: CGFloat = 1

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.masksToBounds = false
    track.addSublayer(knob)
    layer?.addSublayer(track)
    layer?.addSublayer(pointer)
    knob.backgroundColor = NSColor.white.cgColor
    pointer.shadowColor = NSColor.black.cgColor
    pointer.shadowOpacity = 0.25
    pointer.shadowRadius = 1
    pointer.shadowOffset = .zero
    pointer.opacity = 0
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override var isFlipped: Bool { true }

  /// The pointer and the switch have their animations, as QA reports.
  var isAnimating: Bool {
    track.animation(forKey: "flip") != nil && knob.animation(forKey: "flip") != nil
      && pointer.animation(forKey: "move") != nil && pointer.animation(forKey: "show") != nil
  }

  /// Decoration: clicks go through to the page.
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func place(switchFrame: CGRect, scale: CGFloat) {
    guard switchFrame != self.switchFrame || scale != self.scale else { return }
    self.switchFrame = switchFrame
    self.scale = scale
    restart()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    restart()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    restart()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    // The colors are values of the animation: it starts again with the new ones.
    restart()
  }

  /// Lays the layers out and gives them their animation, from the start of a move.
  private func restart() {
    guard window != nil, switchFrame.width > 0, switchFrame.height > 0 else { return }
    var off = CGColor.clear
    var on = CGColor.clear
    var arrow: CGImage?
    effectiveAppearance.performAsCurrentDrawingAppearance {
      off = NSColor(VortexColor.track).cgColor
      on = NSColor.controlAccentColor.cgColor
      arrow = Self.arrowImage(size: 15 * scale, color: NSColor(VortexColor.primaryText))
    }
    let screenScale = window?.backingScaleFactor ?? 2
    let knobSize = switchFrame.height - 3 * scale
    let knobOff = CGPoint(x: switchFrame.minX + 1.5 * scale + knobSize / 2, y: switchFrame.midY)
    let knobOn = CGPoint(x: switchFrame.maxX - 1.5 * scale - knobSize / 2, y: switchFrame.midY)
    // The arrow's tip lands on the switch, coming from below and to the left.
    let pointerSize = CGSize(width: 15 * scale, height: 15 * scale)
    let landed = CGPoint(x: switchFrame.midX + 4 * scale + pointerSize.width / 2, y: switchFrame.midY + 6 * scale)
    let start = CGPoint(x: landed.x - 64 * scale, y: landed.y + 28 * scale)

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for layer in [track, knob, pointer] {
      layer.removeAllAnimations()
      layer.contentsScale = screenScale
    }
    track.frame = switchFrame
    track.cornerRadius = switchFrame.height / 2
    track.backgroundColor = off
    knob.bounds = CGRect(origin: .zero, size: CGSize(width: knobSize, height: knobSize))
    knob.cornerRadius = knobSize / 2
    // The knob is the track's sublayer: its position is in the track's coordinates.
    knob.position = CGPoint(x: knobOff.x - switchFrame.minX, y: knobOff.y - switchFrame.minY)
    pointer.bounds = CGRect(origin: .zero, size: pointerSize)
    pointer.position = start
    pointer.contents = arrow
    pointer.contentsGravity = .resizeAspect
    CATransaction.commit()

    let begin = CACurrentMediaTime()
    let knobOffInTrack = knob.position
    let knobOnInTrack = CGPoint(x: knobOn.x - switchFrame.minX, y: knobOn.y - switchFrame.minY)
    // Seconds into a cycle: the pointer shows and moves 0.15–0.95, the switch turns on 0.95–1.15, stays on, the
    // pointer goes 2.9–3.2, and the switch is off again 3.25–3.3, unseen by the pointer.
    track.add(Self.keyframes("backgroundColor", [off, off, on, on, off, off], at: [0, 0.95, 1.15, 3.25, 3.3, 3.4], begin), forKey: "flip")
    knob.add(
      Self.keyframes("position", [knobOffInTrack, knobOffInTrack, knobOnInTrack, knobOnInTrack, knobOffInTrack, knobOffInTrack].map(NSValue.init(point:)), at: [0, 0.95, 1.15, 3.25, 3.3, 3.4], begin),
      forKey: "flip"
    )
    pointer.add(Self.keyframes("position", [start, start, landed, landed, start].map(NSValue.init(point:)), at: [0, 0.15, 0.95, 3.2, 3.4], begin), forKey: "move")
    pointer.add(Self.keyframes("opacity", [0, 0, 1, 1, 0, 0], at: [0, 0.15, 0.35, 2.9, 3.2, 3.4], begin), forKey: "show")
  }

  /// A keyframe animation over one cycle, repeating for as long as the layer lives; `times` in seconds into a cycle.
  private static func keyframes(_ keyPath: String, _ values: [Any], at times: [CFTimeInterval], _ begin: CFTimeInterval) -> CAKeyframeAnimation {
    let animation = CAKeyframeAnimation(keyPath: keyPath)
    animation.values = values
    animation.keyTimes = times.map { NSNumber(value: $0 / cycle) }
    animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: max(values.count - 1, 1))
    animation.duration = cycle
    animation.repeatCount = .infinity
    animation.beginTime = begin
    animation.isRemovedOnCompletion = false
    return animation
  }

  /// The pointer, drawn from the SF Symbol in the page's text color.
  private static func arrowImage(size: CGFloat, color: NSColor) -> CGImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
      .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let symbol = NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: nil)?
      .withSymbolConfiguration(configuration)
    else { return nil }
    var rect = CGRect(origin: .zero, size: symbol.size)
    return symbol.cgImage(forProposedRect: &rect, context: nil, hints: nil)
  }
}

/// Where the mock's switch is, for the animation laid over it.
struct IllustrationSwitchAnchor: PreferenceKey {
  static let defaultValue: Anchor<CGRect>? = nil

  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
    value = value ?? nextValue()
  }
}
