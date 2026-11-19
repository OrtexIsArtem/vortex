import AppKit
import SwiftUI
import Testing
import VortexCore

@testable import FeatureHome

/// The editor panel's preview of a widget lays it out at its real size before scaling it down to the panel.
@MainActor
struct HomePanelPreviewTests {
  /// The width a widget's view was laid out at.
  @MainActor
  final class Width {
    var value: CGFloat = 0
  }

  /// A notch row widget's preview is as wide as Home's notch row, so its view lays out as it does there.
  @Test
  func aNotchRowWidgetIsPreviewedAsWideAsTheRow() async throws {
    let width = Width()
    let widget = HomeWidget(
      id: "timer.timer",
      feature: "timer",
      title: "Timer",
      place: .notchRow,
      view: GeometryReader { proxy in
        Color.clear.onAppear { width.value = proxy.size.width }
      }
    )
    let window = NSWindow(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 200, height: 120),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.contentView = NSHostingView(rootView: WidgetThumbnail(widget: widget, size: nil))
    window.orderFrontRegardless()
    defer { window.orderOut(nil) }
    let start = ContinuousClock.now
    while width.value == 0, ContinuousClock.now - start < .seconds(2) {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(width.value == HomeView.gridWidth)
  }
}
