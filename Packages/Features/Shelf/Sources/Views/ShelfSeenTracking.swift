import ComposableArchitecture
import SwiftUI
import VortexCore

/// Tells the shelf when the user starts and stops seeing it, in its tab or on Home. `.tabShown` when the window opens
/// on the view or the view appears in the open window; `.tabHidden` when the window closes on it or it leaves the open
/// window. Seeing the shelf ends its fresh marks and starts the flash count over.
///
/// A view mounted or torn down while the window is closed was never seen, so it sends nothing. The shell swaps tabs in
/// the closed window (an ear opens its own feature, the next open goes back to the last tab), and such a swap must not
/// clear the marks before the user has looked at them.
struct ShelfSeenTracking: ViewModifier {
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
