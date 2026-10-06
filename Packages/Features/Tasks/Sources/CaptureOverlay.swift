import AppKit
import ComposableArchitecture
import SwiftUI
import VortexPlatform

/// Shows the frozen screen of a capture while the feature has one, over the display it was taken on.
@MainActor
final class CaptureOverlay: NSObject {
  private let store: StoreOf<TasksFeature>
  private let overlay = ScreenOverlay()
  /// The moment of the capture on screen, so a new capture replaces it and an update does not.
  private var shownCapture: Date?
  private var observation: ObserveToken?

  init(store: StoreOf<TasksFeature>) {
    self.store = store
    super.init()
    observation = observe { [weak self] in self?.update() }
  }

  private func update() {
    guard let capture = store.scope(state: \.capture, action: \.capture) else {
      if overlay.isShown { overlay.close() }
      shownCapture = nil
      return
    }
    // A crosshair while the frame is drawn; then the fields' own pointers.
    overlay.cursor = capture.isFramed ? nil : .crosshair
    guard shownCapture != capture.capturedAt else { return }
    shownCapture = capture.capturedAt
    overlay.show(
      CaptureView(store: capture),
      on: capture.screenshot.displayID,
      onEscape: { capture.send(.cancelTapped) },
      onReturn: { capture.send(.saveTapped) }
    )
  }
}
