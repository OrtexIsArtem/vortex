import AppKit
import QuartzCore
import Testing

@testable import VortexShell

/// A-B5: the illustration's pointer and switch move by Core Animation, so the app does no per-frame work while a page
/// or the panel shows. The window is created but never ordered in: nothing reaches a display.
@MainActor
struct SwitchFlipAnimationTests {
  func placedView() -> (SwitchFlipView, NSWindow) {
    let window = NSWindow(
      contentRect: CGRect(x: -5_000, y: -5_000, width: 300, height: 200),
      styleMask: .borderless,
      backing: .buffered,
      defer: true
    )
    let view = SwitchFlipView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    window.contentView = view
    view.place(switchFrame: CGRect(x: 200, y: 90, width: 26, height: 15), scale: 1)
    return (view, window)
  }

  func animations(of layer: CALayer) -> [CAAnimation] {
    (layer.animationKeys() ?? []).compactMap { layer.animation(forKey: $0) }
      + (layer.sublayers ?? []).flatMap { animations(of: $0) }
  }

  @Test
  func thePointerAndTheSwitchMoveByAnimationsThatRepeatOnTheirOwn() throws {
    let (view, window) = placedView()
    defer { window.contentView = nil }
    let root = try #require(view.layer)
    let all = animations(of: root)
    // The track's color, the knob, the pointer's place and its opacity.
    #expect(all.count == 4)
    for animation in all {
      #expect(animation.repeatCount == .infinity)
      #expect(animation.duration == SwitchFlipView.cycle)
    }
    let keyPaths = Set(all.compactMap { ($0 as? CAPropertyAnimation)?.keyPath })
    #expect(keyPaths == ["backgroundColor", "position", "opacity"])
    #expect(view.isAnimating)
  }

  @Test
  func placingItAgainAtTheSameFrameKeepsTheRunningAnimation() throws {
    let (view, window) = placedView()
    defer { window.contentView = nil }
    let root = try #require(view.layer)
    let before = animations(of: root).map(\.beginTime)
    view.place(switchFrame: CGRect(x: 200, y: 90, width: 26, height: 15), scale: 1)
    #expect(animations(of: root).map(\.beginTime) == before)
  }
}
