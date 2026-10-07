import AppKit
import ComposableArchitecture
import SwiftUI
import VortexPlatform

/// Shows a task's whole screen while the feature has one to show, over the display under the pointer, leaving the
/// app in front as it is.
@MainActor
final class TaskScreenOverlay: NSObject {
  private let store: StoreOf<TasksFeature>
  private let overlay = ScreenOverlay()
  /// What is on screen, so an unrelated change of the tasks does not show it again.
  private var shown: TaskScreen?
  private var observation: ObserveToken?

  init(store: StoreOf<TasksFeature>) {
    self.store = store
    super.init()
    observation = observe { [weak self] in self?.update() }
  }

  private func update() {
    guard let screen = store.screen, let image = screen.image, let task = store.tasks[id: screen.taskID] else {
      if overlay.isShown { overlay.close() }
      shown = nil
      return
    }
    guard shown != screen else { return }
    shown = screen
    let store = store
    overlay.showKeepingFront(
      TaskScreenView(image: image, area: task.cropArea, number: task.number) { store.send(.screenClosed) },
      onDismiss: { store.send(.screenClosed) }
    )
  }
}
