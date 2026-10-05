import AppKit
import SwiftUI
import VortexCore

/// Picks a color with the system color panel. The panel floats above the Vortex window and does not hide while
/// Vortex is in the background; while it is open, the window stays open too (see `OutsideActivity`).
public struct ColorWell: View {
  @Binding private var color: ColorValue
  private let label: Text

  public init(_ label: Text, color: Binding<ColorValue>) {
    self.label = label
    _color = color
  }

  public var body: some View {
    ColorPicker(selection: Binding(get: { color.color }, set: { color = ColorValue($0) }), supportsOpacity: false) {
      label
    }
    .labelsHidden()
    .onAppear { ColorPanelWatcher.shared.prepare() }
  }
}

/// Lifts the shared color panel above Vortex and counts it as outside activity while it is on screen.
@MainActor
private final class ColorPanelWatcher {
  static let shared = ColorPanelWatcher()
  private var isPrepared = false
  private var isCounted = false

  func prepare() {
    guard !isPrepared else { return }
    isPrepared = true
    let panel = NSColorPanel.shared
    panel.level = .aboveVortex
    panel.hidesOnDeactivate = false
    NotificationCenter.default.addObserver(
      forName: NSWindow.didChangeOcclusionStateNotification,
      object: panel,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.panelVisibilityChanged(NSColorPanel.shared.occlusionState.contains(.visible))
      }
    }
  }

  private func panelVisibilityChanged(_ isVisible: Bool) {
    guard isVisible != isCounted else { return }
    isCounted = isVisible
    if isVisible {
      OutsideActivity.shared.begin()
    } else {
      OutsideActivity.shared.end()
    }
  }
}
