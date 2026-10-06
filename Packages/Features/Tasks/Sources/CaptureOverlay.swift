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
    guard shownCapture != capture.capturedAt else { return }
    shownCapture = capture.capturedAt
    overlay.show(
      CaptureView(store: capture),
      on: capture.screenshot.displayID,
      over: capture.source.app?.bundleID,
      onEscape: { capture.send(.cancelTapped) },
      onReturn: { capture.send(.saveTapped) },
      // Another app came to the front, such as a prompt of the system: it must not stay hidden under the frozen screen.
      onInterrupted: { capture.send(.cancelTapped) }
    )
  }
}
