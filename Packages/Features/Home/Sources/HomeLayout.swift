import CoreGraphics
import VortexCore

/// A widget on the grid: its size and its top left cell.
struct Placement: Codable, Equatable, Sendable {
  var widget: String
  var size: HomeWidgetSize
  var column: Int
  var row: Int
  /// Its feature went: the widget doesn't show and its place is free, but it stays in the layout. Kept in home.json, so
  /// a widget coming back after a relaunch still yields to those that showed meanwhile.
  var isAway = false

  init(widget: String, size: HomeWidgetSize, column: Int, row: Int) {
    self.widget = widget
    self.size = size
    self.column = column
    self.row = row
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    widget = try container.decode(String.self, forKey: .widget)
    size = try container.decode(HomeWidgetSize.self, forKey: .size)
    column = try container.decode(Int.self, forKey: .column)
    row = try container.decode(Int.self, forKey: .row)
    isAway = (try? container.decodeIfPresent(Bool.self, forKey: .isAway)) ?? false
  }
}

/// A cell of Home's grid.
struct GridCell: Hashable, Sendable {
  var column: Int
  var row: Int
}

extension Placement {
  /// The cell nearest to the widget's top left corner once it is moved by `offset`, as when it is dragged: wherever it
  /// was grabbed, past half a cell it goes on to the next one.
  func cell(movedBy offset: CGSize) -> GridCell {
    let frame = HomeGrid.frame(column: column, row: row, size: size)
    let column = (frame.minX + offset.width - HomeGrid.sideInset) / (HomeGrid.cell.width + HomeGrid.gap)
    let row = (frame.minY + offset.height) / (HomeGrid.cell.height + HomeGrid.gap)
    return GridCell(column: Int(column.rounded()), row: Int(row.rounded()))
  }
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

  /// The widgets on the grid whose feature runs.
  func visible(_ available: Set<String>) -> [Placement] {
    placed.filter { available.contains($0.widget) }
  }

  /// The widget in the row next to the notch, while its feature runs.
  func notchRowWidget(_ available: Set<String>) -> String? {
    notchRow.flatMap { available.contains($0) ? $0 : nil }
  }

  /// The layout with `widget` put on it as a feature's "Add to Home" puts it: in the notch row while it is free, or at
  /// its first size that fits in the first free place. Unchanged without room, or when the widget shows already.
  func adding(_ widget: HomeWidgetInfo, available: Set<String>) -> HomeLayout {
    let visible = visible(available)
    guard !visible.contains(where: { $0.widget == widget.id }), notchRowWidget(available) != widget.id else { return self }
    var layout = self
    switch widget.place {
    case .notchRow:
      guard notchRowWidget(available) == nil else { return self }
      layout.notchRow = widget.id
    case let .grid(sizes):
      guard let fit = HomeLayout(notchRow: nil, placed: visible).firstFit(sizes, ignoring: []) else { return self }
      layout.placed.append(Placement(widget: widget.id, size: fit.size, column: fit.column, row: fit.row))
    }
    return layout
  }

  /// The layout once the widgets that exist change: a widget whose feature went stays in the layout, away, and its place
  /// is free; one that comes back shows again only where no widget that shows now is, and otherwise leaves the layout.
  func reconciled(available: Set<String>) -> HomeLayout {
    var showing = HomeLayout(notchRow: notchRow, placed: placed.filter { available.contains($0.widget) && !$0.isAway })
    var result: [Placement] = []
    for var placement in placed {
      if !available.contains(placement.widget) {
        placement.isAway = true
        result.append(placement)
      } else if !placement.isAway {
        result.append(placement)
      } else if showing.fits(placement.size, column: placement.column, row: placement.row, ignoring: []) {
        placement.isAway = false
        showing.placed.append(placement)
        result.append(placement)
      }
    }
    return HomeLayout(notchRow: notchRow, placed: result)
  }

  /// The first layout, for a new user and after the update to the grid: the first notch row widget goes there; the
  /// others, in sidebar order, each at its first size that fits, in the first free place. One that fits nowhere stays
  /// off.
  static func initial(_ widgets: [HomeWidgetInfo]) -> HomeLayout {
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
