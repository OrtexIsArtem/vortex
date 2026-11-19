import AppKit
import ComposableArchitecture
import SwiftUI
import VortexPlatform

/// Shows the frozen screen while the feature frames and reads, over the display it was taken on, and closes it once
/// the capture ends: copied, cancelled, or with nothing to read.
@MainActor
final class ScreenTextOverlay: NSObject {
  private let store: StoreOf<ScreenTextFeature>
  let overlay = ScreenOverlay()
  /// The capture on screen, so a new capture replaces it and an update does not.
  private var shown: ScreenTextFeature.Capture.ID?
  private var observation: ObserveToken?

  init(store: StoreOf<ScreenTextFeature>) {
    self.store = store
    super.init()
    observation = observe { [weak self] in self?.update() }
  }

  private func update() {
    guard let capture = store.capture else {
      if overlay.isShown { overlay.close() }
      shown = nil
      return
    }
    guard shown != capture.id else { return }
    shown = capture.id
    let store = store
    overlay.show(
      FramingView(store: store),
      on: capture.screenshot.displayID,
      over: capture.frontApp,
      onEscape: { store.send(.cancelTapped) },
      // Return has nothing to confirm: letting go of the mouse reads the frame.
      onReturn: {},
      // Another app came to the front, such as a prompt of the system, or another frozen screen shows: this one goes.
      onInterrupted: { store.send(.cancelTapped) }
    )
  }
}
