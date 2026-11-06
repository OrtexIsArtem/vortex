import ComposableArchitecture
import SwiftUI
import VortexCore

/// Tells the shelf when it shows and hides, in its tab or on Home. `.tabShown` when the window opens on the view or the
/// view appears in the open window: the shelf looks up its files, so missing ones are marked. `.tabHidden` when the
/// window closes on it or it leaves the open window: Quick Look closes.
///
/// A view mounted or torn down while the window is closed is not on screen, so it sends nothing. The shell swaps tabs
/// in the closed window: an ear opens its own feature, and the next open goes back to the last tab.
struct ShelfVisibilityTracking: ViewModifier {
  let store: StoreOf<ShelfFeature>
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
