import CoreGraphics
import VortexCore

/// A widget as Home sees it, without its view: what the layout and the editor need. Names are in the app's language.
struct WidgetInfo: Equatable, Sendable {
  var id: String
  var feature: FeatureID
  var place: HomeWidgetPlace
  var name: String
  var featureName: String
  var featureSymbol: String
}

/// A widget on the grid: its size and its top left cell.
struct Placement: Codable, Equatable, Sendable {
  var widget: String
  var size: HomeWidgetSize
  var column: Int
  var row: Int
}

/// Where the widgets are on Home: one in the row next to the notch, the rest on the 4×2 grid. Widgets never overlap and
/// never leave the grid; places that free up stay free.
struct HomeLayout: Codable, Equatable, Sendable {
  var notchRow: String?
  var placed: [Placement] = []

  /// Whether a widget of `size` fits with its top left cell at `column`, `row`: inside the grid and on no other widget's
  /// cells, those in `ignoring` left out.
  func fits(_ size: HomeWidgetSize, column: Int, row: Int, ignoring: Set<String>) -> Bool {
    guard column >= 0, row >= 0, column + size.columns <= HomeGrid.columns, row + size.rows <= HomeGrid.rows else {
      return false
    }
    return !placed.contains { other in
      !ignoring.contains(other.widget)
        && column < other.column + other.size.columns && other.column < column + size.columns
        && row < other.row + other.size.rows && other.row < row + size.rows
    }
  }

  /// The first of `sizes` that fits somewhere, at its first free place: left to right, then top to bottom.
  func firstFit(_ sizes: [HomeWidgetSize], ignoring: Set<String>) -> (size: HomeWidgetSize, column: Int, row: Int)? {
    for size in sizes {
      for row in 0..<HomeGrid.rows {
        for column in 0..<HomeGrid.columns where fits(size, column: column, row: row, ignoring: ignoring) {
          return (size, column, row)
        }
      }
    }
    return nil
  }

  /// The first layout, for a new user and after the update to the grid: the first notch row widget goes there; the
  /// others, in sidebar order, each at its first size that fits, in the first free place. One that fits nowhere stays
  /// off.
  static func initial(_ widgets: [WidgetInfo]) -> HomeLayout {
    var layout = HomeLayout()
    for widget in widgets {
      switch widget.place {
      case .notchRow:
        if layout.notchRow == nil { layout.notchRow = widget.id }
      case let .grid(sizes):
        if let fit = layout.firstFit(sizes, ignoring: []) {
          layout.placed.append(Placement(widget: widget.id, size: fit.size, column: fit.column, row: fit.row))
        }
      }
    }
    return layout
  }
}
