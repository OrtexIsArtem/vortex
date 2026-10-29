import AppKit
import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The onboarding's own standard window and its guide panel (S6, S15, S34, S60, S61, S79). In a QA run both stay off
/// the displays, never take the keyboard and never bring Vortex to the front.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
  static let shared = OnboardingWindowController()

  static let windowSize = CGSize(width: 560, height: 620)
  static let panelSize = CGSize(width: 340, height: 300)

  private(set) var window: OnboardingWindow?
  private(set) var panel: OnboardingPanel?
  /// The close button and ⌘W (S10, S60).
  var onClose: () -> Void = {}
  /// Esc; it closes only a single page (S79).
  var onEscape: () -> Void = {}
  /// ⌘Q quits Vortex (S42).
  var onQuit: () -> Void = {}
  /// The app in front before the window showed; it gets the front back after a single page closes (S61).
  private var appBefore: NSRunningApplication?
  /// Where the window was before it turned into the panel (S61).
  private var lastFrame: CGRect?
  private var placementTask: Task<Void, Never>?
  private let isQA: Bool

  override private init() {
    #if DEBUG
      isQA = QA.isActive
    #else
      isQA = false
    #endif
    super.init()
  }

  func install(window content: some View, panel panelContent: some View) {
    let window = OnboardingWindow(content: content)
    window.delegate = self
    window.onEscape = { [weak self] in self?.onEscape() }
    window.onQuit = { [weak self] in self?.onQuit() }
    self.window = window
    panel = OnboardingPanel(content: panelContent)
    #if DEBUG
      if isQA {
        QA.registerWindow(id: "onboarding") { [weak self] in self?.window }
        QA.registerWindow(id: "onboarding-panel") { [weak self] in self?.panel }
      }
    #endif
  }

  func present(_ mode: OnboardingWindowMode, activate: Bool) {
    guard let window, let panel else { return }
    switch mode {
    case .window:
      placementTask?.cancel()
      panel.orderOut(nil)
      if !window.isVisible { window.setFrame(windowFrame(), display: false) }
      show(window, activate: activate)
    case .panel:
      if window.isVisible {
        lastFrame = window.frame
        window.orderOut(nil)
      }
      placePanel()
    case .panelHidden:
      placementTask?.cancel()
      panel.orderOut(nil)
    }
  }

  func hide(restoreFront: Bool) {
    placementTask?.cancel()
    window?.orderOut(nil)
    panel?.orderOut(nil)
    lastFrame = nil
    defer { appBefore = nil }
    guard restoreFront, !isQA, NSApp.isActive, let app = appBefore, !app.isTerminated else { return }
    app.activate(from: .current)
  }

  // MARK: - NSWindowDelegate

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    // The reducer decides: hide and keep the progress (S10), or close a single page (S60).
    onClose()
    return false
  }

  // MARK: - Placement

  private func show(_ window: NSWindow, activate: Bool) {
    if isQA {
      // Never key, never in front (QA.allowsKeyWindows, the window guard).
      window.setFrame(QA.offscreen(window.frame), display: false)
      window.orderFront(nil)
      return
    }
    if activate {
      if !NSApp.isActive, let front = NSWorkspace.shared.frontmostApplication, front != .current { appBefore = front }
      NSApp.activate()
      window.makeKeyAndOrderFront(nil)
    } else {
      // A hover shows the window without making it key (S46).
      window.orderFrontRegardless()
    }
  }

  /// Back from the panel: its last place on its display, or the pointer's display if that one is gone. From hidden:
  /// centered on the pointer's display (S61, S79).
  private func windowFrame() -> CGRect {
    let size = Self.windowSize
    if isQA { return QA.offscreen(CGRect(origin: .zero, size: size)) }
    if let lastFrame, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(lastFrame) }) {
      return lastFrame
    }
    let pointer = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
    let area = screen?.visibleFrame ?? CGRect(origin: .zero, size: size)
    return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
      .integral
  }

  /// Right of System Settings' window, or left of it, or at the bottom right of its display (S15); placed again on
  /// each activation (S73).
  private func placePanel() {
    guard let panel else { return }
    placementTask?.cancel()
    placementTask = Task { [weak self, isQA] in
      @Dependency(\.activeAppClient) var activeApp
      let frames = await activeApp.windowFrames(OnboardingFeature.systemSettingsID)
      guard let self, !Task.isCancelled else { return }
      let size = Self.panelSize
      let frame: CGRect
      if isQA {
        frame = QA.offscreen(CGRect(origin: .zero, size: size))
      } else {
        frame = Self.panelFrame(next: frames.first, size: size, screens: NSScreen.screens.map(\.visibleFrame))
      }
      panel.setFrame(frame, display: false)
      panel.orderFrontRegardless()
      _ = self
    }
  }

  /// Where the panel goes for a System Settings window at `settings`, on displays with these visible frames.
  nonisolated static func panelFrame(next settings: CGRect?, size: CGSize, screens: [CGRect], gap: CGFloat = 12) -> CGRect {
    let fallbackScreen = screens.first ?? CGRect(origin: .zero, size: CGSize(width: 1_440, height: 900))
    guard let settings else {
      return CGRect(x: fallbackScreen.maxX - size.width - 20, y: fallbackScreen.minY + 20, width: size.width, height: size.height)
    }
    let screen = screens.first { $0.intersects(settings) } ?? fallbackScreen
    let y = min(max(settings.maxY - size.height, screen.minY), screen.maxY - size.height)
    let right = CGRect(x: settings.maxX + gap, y: y, width: size.width, height: size.height)
    if screen.contains(right) { return right }
    let left = CGRect(x: settings.minX - gap - size.width, y: y, width: size.width, height: size.height)
    if screen.contains(left) { return left }
    return CGRect(x: screen.maxX - size.width - 20, y: screen.minY + 20, width: size.width, height: size.height)
  }
}

/// A standard window with only the close button, a fixed size and no full screen (S60, S79).
final class OnboardingWindow: NSWindow {
  var onEscape: (() -> Void)?
  var onQuit: (() -> Void)?

  init(content: some View) {
    super.init(
      contentRect: CGRect(origin: .zero, size: OnboardingWindowController.windowSize),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: true
    )
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    title = "Vortex"
    isReleasedWhenClosed = false
    isMovableByWindowBackground = true
    animationBehavior = .none
    collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden = true
    let hosting = NSHostingView(rootView: content)
    hosting.sizingOptions = []
    contentView = hosting
  }

  override var canBecomeKey: Bool {
    #if DEBUG
      // A QA run's windows never take the keyboard (QA.allowsKeyWindows).
      guard QA.allowsKeyWindows else { return false }
    #endif
    return true
  }

  override var canBecomeMain: Bool {
    #if DEBUG
      guard QA.allowsKeyWindows else { return false }
    #endif
    return true
  }

  override func cancelOperation(_ sender: Any?) {
    onEscape?()
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
      switch key {
      case "w":
        performClose(nil)
        return true
      case "q":
        onQuit?()
        return true
      default: break
      }
    }
    return super.performKeyEquivalent(with: event)
  }
}

/// The guide panel: floats next to System Settings, never takes focus and has no close control (S15, S73).
final class OnboardingPanel: NSPanel {
  init(content: some View) {
    super.init(
      contentRect: CGRect(origin: .zero, size: OnboardingWindowController.panelSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: true
    )
    isFloatingPanel = true
    level = .floating
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    animationBehavior = .none
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isMovableByWindowBackground = true
    let hosting = NSHostingView(rootView: content)
    hosting.sizingOptions = []
    contentView = hosting
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
