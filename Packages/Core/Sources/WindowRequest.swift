import SwiftUI

/// What a feature's tab asks of the window while it shows: a size, and the focus. While a tab has the focus, the sidebar
/// dims and the other tabs and their shortcuts wait. The shell forgets every request when the window closes.
public struct WindowRequest: Equatable, Sendable {
  public var size: WindowSize
  public var isFocused: Bool

  public init(size: WindowSize, isFocused: Bool = false) {
    self.size = size
    self.isFocused = isFocused
  }

  /// The window every tab has without asking.
  public static let regular = WindowRequest(size: .regular)
}

extension EnvironmentValues {
  /// Asks the shell for the window the feature's tab needs, until the tab asks again or the window closes; nil outside
  /// a feature's tab.
  @Entry public var windowRequest: (@MainActor (WindowRequest) -> Void)? = nil
  /// Leaves the feature's tab for the catalog, giving the focus back first; nil outside a feature's tab.
  @Entry public var showCatalog: (@MainActor () -> Void)? = nil
}
