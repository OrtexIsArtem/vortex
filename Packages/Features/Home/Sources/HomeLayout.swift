import CoreGraphics
import VortexCore

/// A widget on the grid: its size and its top left cell.
struct Placement: Codable, Equatable, Sendable {
  var widget: String
  var size: HomeWidgetSize
  var column: Int
  var row: Int
  /// Set while its feature doesn't run: the widget doesn't show and its place is free, but it stays in the layout. The
  /// number orders the widgets that went: the higher, the later. Kept in home.json, so a widget coming back after a
  /// relaunch still yields to those that showed after it went.
  var away: Int?

  var isAway: Bool { away != nil }

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
    away = try? container.decodeIfPresent(Int.self, forKey: .away)
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

/// Where the widgets are on Home: one in the row next to the notch, the rest on the 4×2 grid, and where the utilities
/// button floats. Widgets never overlap and never leave the grid; places that free up stay free.
struct HomeLayout: Codable, Equatable, Sendable {
  var notchRow: String?
  var placed: [Placement] = []
  /// The utilities button's place, where the editor dragged it: its circle's center, in points from the middle of
  /// Home's column and from its top, so it keeps its spot over the grid and its side of the notch on every notch width.
  /// Nil in its slot at the notch row's right end, as a home.json without it reads.
  var button: CGPoint?

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
  /// is free. One that comes back shows again only where no widget that shows now is; among those coming back, the one
  /// that went last, so showed last, goes first. One that finds no room leaves the layout.
  func reconciled(available: Set<String>) -> HomeLayout {
    var showing = HomeLayout(notchRow: notchRow, placed: placed.filter { available.contains($0.widget) && !$0.isAway })
    // Widgets that go now went later than every widget away before them.
    let goingNow = (placed.compactMap(\.away).max() ?? 0) + 1
    var result = placed
    for index in result.indices where !available.contains(result[index].widget) {
      result[index].away = result[index].away ?? goingNow
    }
    let returning = result.indices
      .filter { result[$0].isAway && available.contains(result[$0].widget) }
      .sorted { ((result[$0].away ?? 0), -$0) > ((result[$1].away ?? 0), -$1) }
    var leaving: Set<Int> = []
    for index in returning {
      let placement = result[index]
      if showing.fits(placement.size, column: placement.column, row: placement.row, ignoring: []) {
        result[index].away = nil
        showing.placed.append(result[index])
      } else {
        leaving.insert(index)
      }
    }
    return HomeLayout(
      notchRow: notchRow, placed: result.indices.filter { !leaving.contains($0) }.map { result[$0] }, button: button
    )
  }

  /// The layout once `widget`, dragged, lands with its top left cell at `column`, `row`, and the widgets in its way move
  /// aside. They first take the place it left, keeping how they lay: each moves by the reverse of the drag. One that
  /// doesn't fit there goes to the nearest free place. Widgets not in the way move only when that is the only way to make
  /// room. Away widgets take no part: their places are free, and they keep them; so does the notch row. Nil when the
  /// widget doesn't show on the grid, is there already, or the others can't all fit around it.
  func moving(_ widget: String, column: Int, row: Int, available: Set<String>) -> HomeLayout? {
    let shown = placed.indices.filter { available.contains(placed[$0].widget) }
    guard let draggedIndex = shown.first(where: { placed[$0].widget == widget }) else { return nil }
    let dragged = placed[draggedIndex]
    guard column != dragged.column || row != dragged.row,
          let landing = GridMask(dragged.size, column: column, row: row)
    else { return nil }
    let others = shown.filter { $0 != draggedIndex }
    let spots = others.map { index in
      let other = placed[index]
      let swap = GridCell(column: other.column - (column - dragged.column), row: other.row - (row - dragged.row))
      return MoveSpot.all(for: other, swap: swap)
    }
    // Every arrangement of the others around the dragged widget, by branch and bound: the cost only grows as widgets are
    // placed, so a branch that costs as much as the best arrangement so far can't beat it, and a tie keeps the first.
    var best: (cost: MoveCost, spots: [MoveSpot])?
    var chosen: [MoveSpot] = []
    func place(_ index: Int, taken: GridMask, cost: MoveCost) {
      if let best, cost >= best.cost { return }
      guard index < spots.count else {
        best = (cost, chosen)
        return
      }
      for spot in spots[index] where !taken.overlaps(spot.mask) {
        chosen.append(spot)
        place(index + 1, taken: taken.union(spot.mask), cost: cost + spot.cost)
        chosen.removeLast()
      }
    }
    place(0, taken: landing, cost: MoveCost())
    guard let best else { return nil }
    var layout = self
    layout.placed[draggedIndex].column = column
    layout.placed[draggedIndex].row = row
    for (index, spot) in zip(others, best.spots) {
      layout.placed[index].column = spot.cell.column
      layout.placed[index].row = spot.cell.row
    }
    return layout
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

// MARK: - The utilities button

extension HomeLayout {
  /// How far the utilities button's center keeps from Home's column's edges and from the notch: its 28 pt circle's
  /// radius and 8 pt, as in its slot.
  private static let buttonInset: CGFloat = 14 + 8

  /// The utilities button's slot at the notch row's right end, as its center from the top left of Home's column on a
  /// display whose notch cuts in at `notch` (nil without one): the circle 8 pt from the column's right edge, in the
  /// middle of the row.
  static func buttonSlot(notch: CGRect?) -> CGPoint {
    CGPoint(x: HomeView.width(notchWidth: notch?.width) - buttonInset, y: VortexMetrics.headerHeight / 2)
  }

  /// Where the utilities button's center shows, from the top left of Home's column: in its slot without a place;
  /// otherwise at its place or, where that doesn't fit, as in a narrower notch's narrower column, at the nearest point
  /// that does: the circle 8 pt inside the column, and 8 pt clear of the notch, beside it or below it.
  static func buttonCenter(_ place: CGPoint?, notch: CGRect?) -> CGPoint {
    guard let place else { return buttonSlot(notch: notch) }
    let width = HomeView.width(notchWidth: notch?.width)
    var center = CGPoint(
      x: min(max(width / 2 + place.x, buttonInset), width - buttonInset),
      y: min(max(place.y, buttonInset), WindowSize.regular.size.height - buttonInset)
    )
    if let clear = notch?.insetBy(dx: -buttonInset, dy: -buttonInset), clear.contains(center) {
      let left = center.x - clear.minX, right = clear.maxX - center.x, below = clear.maxY - center.y
      if left <= min(right, below) {
        center.x = clear.minX
      } else if right <= below {
        center.x = clear.maxX
      } else {
        center.y = clear.maxY
      }
    }
    return center
  }

  /// The utilities button's place once a drag drops its center at `point`, from the top left of Home's column: where it
  /// then shows (`buttonCenter`), in whole points, or nil, its slot, within 20 pt of the slot's center.
  static func buttonPlace(droppedAt point: CGPoint, notch: CGRect?) -> CGPoint? {
    let middle = HomeView.width(notchWidth: notch?.width) / 2
    let center = buttonCenter(CGPoint(x: point.x - middle, y: point.y), notch: notch)
    let slot = buttonSlot(notch: notch)
    guard hypot(center.x - slot.x, center.y - slot.y) > 20 else { return nil }
    return CGPoint(x: (center.x - middle).rounded(), y: center.y.rounded())
  }
}

/// Cells of the grid as bits, row by row: bit `row × columns + column`.
private struct GridMask {
  var bits: UInt64 = 0

  /// The cells a widget of `size` covers with its top left cell at `column`, `row`; nil when it would leave the grid.
  init?(_ size: HomeWidgetSize, column: Int, row: Int) {
    guard column >= 0, row >= 0, column + size.columns <= HomeGrid.columns, row + size.rows <= HomeGrid.rows else {
      return nil
    }
    for cellRow in row..<row + size.rows {
      for cellColumn in column..<column + size.columns {
        bits |= 1 << (cellRow * HomeGrid.columns + cellColumn)
      }
    }
  }

  private init(bits: UInt64) {
    self.bits = bits
  }

  func overlaps(_ other: GridMask) -> Bool {
    bits & other.bits != 0
  }

  func union(_ other: GridMask) -> GridMask {
    GridMask(bits: bits | other.bits)
  }
}

/// What moving the other widgets costs, compared in order: how many moved, how many of those aren't at their swap
/// place, and how far they went, as the sum of squared distances in cells.
private struct MoveCost: Comparable {
  var moved = 0
  var offSwap = 0
  var distance = 0

  static func < (lhs: Self, rhs: Self) -> Bool {
    (lhs.moved, lhs.offSwap, lhs.distance) < (rhs.moved, rhs.offSwap, rhs.distance)
  }

  static func + (lhs: Self, rhs: Self) -> Self {
    MoveCost(moved: lhs.moved + rhs.moved, offSwap: lhs.offSwap + rhs.offSwap, distance: lhs.distance + rhs.distance)
  }
}

/// A place a widget can take while another one is dragged, and what taking it costs.
private struct MoveSpot {
  var cell: GridCell
  var mask: GridMask
  var cost: MoveCost

  /// Every place on the grid that takes `placement`'s size, in the order tried: its own, its swap place, then the
  /// others nearest first, in reading order.
  static func all(for placement: Placement, swap: GridCell) -> [MoveSpot] {
    let own = GridCell(column: placement.column, row: placement.row)
    var spots: [MoveSpot] = []
    for row in 0..<HomeGrid.rows {
      for column in 0..<HomeGrid.columns {
        guard let mask = GridMask(placement.size, column: column, row: row) else { continue }
        let cell = GridCell(column: column, row: row)
        let distance = (column - own.column) * (column - own.column) + (row - own.row) * (row - own.row)
        let cost = MoveCost(moved: cell == own ? 0 : 1, offSwap: cell == own || cell == swap ? 0 : 1, distance: distance)
        spots.append(MoveSpot(cell: cell, mask: mask, cost: cost))
      }
    }
    return spots.sorted {
      ($0.cost.moved, $0.cost.offSwap, $0.cost.distance, $0.cell.row, $0.cell.column)
        < ($1.cost.moved, $1.cost.offSwap, $1.cost.distance, $1.cell.row, $1.cell.column)
    }
  }
}
