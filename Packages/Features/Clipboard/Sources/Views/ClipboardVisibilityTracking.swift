import ComposableArchitecture
import SwiftUI
import VortexCore

/// Tells the clipboard when its tab or its widget on Home shows and hides. `.tabShown` when the window opens on the view
/// or the view appears in the open window: revealed secrets hide, the search empties, files are checked. `.tabHidden`
/// when the window closes on it or it leaves the open window: Quick Look closes.
///
/// A view mounted or torn down while the window is closed is not on screen, so it sends nothing.
struct ClipboardVisibilityTracking: ViewModifier {
  let store: StoreOf<ClipboardFeature>
  /// Runs right after `.tabShown`.
  var onShown: () -> Void = {}
  @Environment(\.isWindowOpen) private var isWindowOpen

  func body(content: Content) -> some View {
    content
      .task(id: isWindowOpen) {
        guard isWindowOpen else { return }
        store.send(.tabShown)
        onShown()
      }
      .onChange(of: isWindowOpen) { wasOpen, isOpen in
        if wasOpen, !isOpen { store.send(.tabHidden) }
      }
      .onDisappear {
        if isWindowOpen { store.send(.tabHidden) }
      }
  }
}
