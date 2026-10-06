import CoreGraphics
import VortexCore

/// Which widget goes where on Home: one in the row next to the notch, the middle top to bottom, the dock side by side.
/// Widgets come in sidebar order.
struct HomeLayout {
  /// The dock's height while something is in the middle.
  static let fixedDockHeight: CGFloat = 160

  var header: HomeWidget?
  var main: [HomeWidget]
  var dock: [HomeWidget]

  init(_ widgets: [HomeWidget]) {
    header = widgets.first { $0.slot == .header }
    main = widgets.filter { $0.slot == .main }
    dock = widgets.filter { $0.slot == .dock }
  }

  var isEmpty: Bool {
    header == nil && main.isEmpty && dock.isEmpty
  }

  /// The dock keeps its height under the middle; with nothing in the middle it takes all the room (nil).
  var dockHeight: CGFloat? {
    main.isEmpty ? nil : Self.fixedDockHeight
  }
}
