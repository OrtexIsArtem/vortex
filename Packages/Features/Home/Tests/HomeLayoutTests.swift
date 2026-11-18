import Foundation
import Testing
import VortexCore

@testable import FeatureHome

/// Where widgets go on the 4×2 grid.
struct HomeLayoutTests {
  func info(_ id: String, _ place: HomeWidgetPlace) -> WidgetInfo {
    let feature = String(id.split(separator: ".")[0])
    return WidgetInfo(id: id, feature: feature, place: place, name: id, featureName: feature, featureSymbol: "square")
  }

  /// Widgets in sidebar order, each at its first size that fits, in the first free place: today's Home.
  @Test
  func theFirstLayoutPutsEachWidgetAtItsFirstSizeThatFits() {
    let layout = HomeLayout.initial([
      info("timer.timer", .notchRow),
      info("clipboard.history", .grid([.large, .medium])),
      info("shelf.files", .grid([.medium, .wide])),
    ])
    #expect(layout.notchRow == "timer.timer")
    #expect(layout.placed == [
      Placement(widget: "clipboard.history", size: .large, column: 0, row: 0),
      Placement(widget: "shelf.files", size: .medium, column: 2, row: 0),
    ])
  }

  @Test
  func firstFitScansLeftToRightThenTopToBottom() {
    var layout = HomeLayout(notchRow: nil, placed: [Placement(widget: "a", size: .large, column: 0, row: 0)])
    var fit = layout.firstFit([.small], ignoring: [])
    #expect(fit?.size == .small && fit?.column == 2 && fit?.row == 0)
    layout.placed.append(Placement(widget: "b", size: .small, column: 2, row: 0))
    fit = layout.firstFit([.small], ignoring: [])
    #expect(fit?.column == 3 && fit?.row == 0)
    layout.placed.append(Placement(widget: "c", size: .small, column: 3, row: 0))
    fit = layout.firstFit([.wide, .medium], ignoring: [])
    #expect(fit?.size == .medium && fit?.column == 2 && fit?.row == 1)
  }

  @Test
  func fitsKeepsWidgetsInsideTheGridAndApart() {
    let layout = HomeLayout(notchRow: nil, placed: [Placement(widget: "a", size: .large, column: 0, row: 0)])
    #expect(!layout.fits(.wide, column: 2, row: 0, ignoring: []))
    #expect(!layout.fits(.small, column: 1, row: 1, ignoring: []))
    #expect(layout.fits(.small, column: 1, row: 1, ignoring: ["a"]))
    #expect(layout.fits(.medium, column: 2, row: 1, ignoring: []))
  }

  @Test
  func aWidgetThatFitsNowhereStaysOff() {
    let full = HomeLayout(notchRow: nil, placed: [Placement(widget: "player", size: .full, column: 0, row: 0)])
    #expect(full.firstFit([.medium, .small], ignoring: []) == nil)
    let twoRows = HomeLayout.initial([info("timer.timer", .notchRow), info("clock.row", .notchRow)])
    #expect(twoRows.notchRow == "timer.timer" && twoRows.placed.isEmpty)
  }

  /// A dragged widget lands on the cell nearest to its top left corner, wherever it was grabbed.
  @Test
  func aDraggedWidgetLandsOnTheCellNearestItsCorner() {
    let shelf = Placement(widget: "shelf.files", size: .medium, column: 2, row: 0)
    #expect(shelf.cell(movedBy: .zero) == GridCell(column: 2, row: 0))
    #expect(shelf.cell(movedBy: CGSize(width: 0, height: 194)) == GridCell(column: 2, row: 1))
    #expect(shelf.cell(movedBy: CGSize(width: -150, height: 10)) == GridCell(column: 1, row: 0))
    // Past half a cell it goes on to the next one.
    #expect(shelf.cell(movedBy: CGSize(width: 80, height: 100)) == GridCell(column: 3, row: 1))
    #expect(shelf.cell(movedBy: CGSize(width: 70, height: 90)) == GridCell(column: 2, row: 0))
  }

  /// A place written without `isAway`, by hand or by a build before it, reads as a widget that shows.
  @Test
  func aPlaceSavedWithoutAwayShows() throws {
    let json = Data(#"{"widget":"clipboard.history","size":"large","column":0,"row":0}"#.utf8)
    let placement = try JSONDecoder().decode(Placement.self, from: json)
    #expect(placement == Placement(widget: "clipboard.history", size: .large, column: 0, row: 0))
    #expect(!placement.isAway)
  }
}
