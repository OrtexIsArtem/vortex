import Foundation
import Testing
import VortexCore

@testable import FeatureHome

/// Where widgets go on the 4×2 grid.
struct HomeLayoutTests {
  func info(_ id: String, _ place: HomeWidgetPlace) -> HomeWidgetInfo {
    let feature = String(id.split(separator: ".")[0])
    return HomeWidgetInfo(id: id, feature: feature, place: place, name: id, featureName: feature, featureSymbol: "square")
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

  // MARK: - Moving a widget onto others

  /// The owner's Home: Shelf medium at (0,0), Clipboard's history large at (2,0), Timer in the notch row.
  var ownersHome: HomeLayout {
    HomeLayout(notchRow: "timer.timer", placed: [
      Placement(widget: "shelf.files", size: .medium, column: 0, row: 0),
      Placement(widget: "clipboard.history", size: .large, column: 2, row: 0),
    ])
  }

  let ownersWidgets: Set<String> = ["timer.timer", "shelf.files", "clipboard.history"]

  /// Dragged onto another widget, a widget takes its place, and the other takes the place it left: they swap. The notch
  /// row and the order of the places stay.
  @Test
  func draggedOntoAnotherWidgetTheyTradePlaces() {
    let clipboardFirst = ownersHome.moving("clipboard.history", column: 0, row: 0, available: ownersWidgets)
    #expect(clipboardFirst == HomeLayout(notchRow: "timer.timer", placed: [
      Placement(widget: "shelf.files", size: .medium, column: 2, row: 0),
      Placement(widget: "clipboard.history", size: .large, column: 0, row: 0),
    ]))
    let shelfLast = ownersHome.moving("shelf.files", column: 2, row: 0, available: ownersWidgets)
    #expect(shelfLast == clipboardFirst)
  }

  /// A widget in the way whose swap place is off the grid goes to the nearest free place.
  @Test
  func aWidgetWithoutRoomAtItsSwapPlaceGoesToTheNearestFreePlace() {
    // Clipboard's swap place would be (0,-1).
    #expect(ownersHome.moving("shelf.files", column: 2, row: 1, available: ownersWidgets)?.placed == [
      Placement(widget: "shelf.files", size: .medium, column: 2, row: 1),
      Placement(widget: "clipboard.history", size: .large, column: 0, row: 0),
    ])
  }

  /// The widgets in the way keep how they lay: each moves by the reverse of the drag.
  @Test
  func theWidgetsInTheWayKeepHowTheyLay() {
    let layout = HomeLayout(notchRow: nil, placed: [
      Placement(widget: "a.small", size: .small, column: 0, row: 0),
      Placement(widget: "b.small", size: .small, column: 1, row: 0),
      Placement(widget: "m.medium", size: .medium, column: 2, row: 0),
    ])
    #expect(layout.moving("m.medium", column: 0, row: 0, available: ["a.small", "b.small", "m.medium"])?.placed == [
      Placement(widget: "a.small", size: .small, column: 2, row: 0),
      Placement(widget: "b.small", size: .small, column: 3, row: 0),
      Placement(widget: "m.medium", size: .medium, column: 0, row: 0),
    ])
  }

  /// The swap place wins over a nearer free place.
  @Test
  func theSwapPlaceBeatsTheNearestFreePlace() {
    let layout = HomeLayout(notchRow: nil, placed: [
      Placement(widget: "x.small", size: .small, column: 0, row: 0),
      Placement(widget: "y.small", size: .small, column: 3, row: 0),
    ])
    #expect(layout.moving("y.small", column: 0, row: 0, available: ["x.small", "y.small"])?.placed == [
      Placement(widget: "x.small", size: .small, column: 3, row: 0),
      Placement(widget: "y.small", size: .small, column: 0, row: 0),
    ])
  }

  /// Between places as near, the first in reading order wins: left to right, then top to bottom.
  @Test
  func betweenPlacesAsNearReadingOrderWins() {
    let layout = HomeLayout(notchRow: nil, placed: [
      Placement(widget: "d.small", size: .small, column: 0, row: 0),
      Placement(widget: "x.medium", size: .medium, column: 1, row: 0),
    ])
    // X's swap place, (0,0), takes D's new cell; (2,0) and (1,1) are as near.
    #expect(layout.moving("d.small", column: 1, row: 0, available: ["d.small", "x.medium"])?.placed == [
      Placement(widget: "d.small", size: .small, column: 1, row: 0),
      Placement(widget: "x.medium", size: .medium, column: 2, row: 0),
    ])
  }

  /// On a full grid the widgets not in the way move too, as that is the only way to make room, each as little as it can.
  @Test
  func widgetsNotInTheWayMoveOnlyToMakeRoom() {
    let layout = HomeLayout(notchRow: nil, placed: [
      Placement(widget: "l.large", size: .large, column: 0, row: 0),
      Placement(widget: "m.medium", size: .medium, column: 2, row: 0),
      Placement(widget: "a.small", size: .small, column: 2, row: 1),
      Placement(widget: "b.small", size: .small, column: 3, row: 1),
    ])
    let available: Set<String> = ["l.large", "m.medium", "a.small", "b.small"]
    #expect(layout.moving("m.medium", column: 0, row: 0, available: available)?.placed == [
      Placement(widget: "l.large", size: .large, column: 2, row: 0),
      Placement(widget: "m.medium", size: .medium, column: 0, row: 0),
      Placement(widget: "a.small", size: .small, column: 0, row: 1),
      Placement(widget: "b.small", size: .small, column: 1, row: 1),
    ])
  }

  /// A widget in the way doesn't push one that isn't out of its swap place: it goes to the nearest free place instead.
  @Test
  func aWidgetNotInTheWayStaysWhileThereIsRoomElsewhere() {
    let layout = HomeLayout(notchRow: nil, placed: [
      Placement(widget: "w.medium", size: .medium, column: 2, row: 0),
      Placement(widget: "d.small", size: .small, column: 2, row: 1),
      Placement(widget: "n.small", size: .small, column: 3, row: 1),
    ])
    // W's swap place, (2,1), would push N.
    #expect(layout.moving("d.small", column: 2, row: 0, available: ["w.medium", "d.small", "n.small"])?.placed == [
      Placement(widget: "w.medium", size: .medium, column: 1, row: 1),
      Placement(widget: "d.small", size: .small, column: 2, row: 0),
      Placement(widget: "n.small", size: .small, column: 3, row: 1),
    ])
  }

  /// Fewer widgets moving beats more of them at their swap places.
  @Test
  func fewerWidgetsMovingBeatsSwapPlaces() {
    let layout = HomeLayout(notchRow: nil, placed: [
      Placement(widget: "a.small", size: .small, column: 1, row: 0),
      Placement(widget: "b.small", size: .small, column: 2, row: 0),
      Placement(widget: "d.medium", size: .medium, column: 0, row: 1),
      Placement(widget: "n.medium", size: .medium, column: 2, row: 1),
    ])
    // D lands on N's swap place, and every place in the top row pushes A or B. B takes the corner N leaves, rather than
    // A and B both moving left to their swap places.
    let available: Set<String> = ["a.small", "b.small", "d.medium", "n.medium"]
    #expect(layout.moving("d.medium", column: 1, row: 1, available: available)?.placed == [
      Placement(widget: "a.small", size: .small, column: 1, row: 0),
      Placement(widget: "b.small", size: .small, column: 3, row: 1),
      Placement(widget: "d.medium", size: .medium, column: 1, row: 1),
      Placement(widget: "n.medium", size: .medium, column: 2, row: 0),
    ])
  }

  /// Where the widgets in the way can't all fit, nothing moves; nor past the grid's edge, onto the widget's own place, or
  /// for a widget that doesn't show on the grid.
  @Test
  func aWidgetThatCantGoThereMovesNothing() {
    #expect(ownersHome.moving("clipboard.history", column: 1, row: 0, available: ownersWidgets) == nil)
    #expect(ownersHome.moving("shelf.files", column: 3, row: 0, available: ownersWidgets) == nil)
    #expect(ownersHome.moving("shelf.files", column: 0, row: -1, available: ownersWidgets) == nil)
    #expect(ownersHome.moving("shelf.files", column: 0, row: 0, available: ownersWidgets) == nil)
    #expect(ownersHome.moving("timer.timer", column: 0, row: 1, available: ownersWidgets) == nil)
    #expect(ownersHome.moving("shelf.files", column: 0, row: 1, available: ["clipboard.history"]) == nil)
  }

  /// An away widget takes no part: its place is free for the others, and it keeps it.
  @Test
  func anAwayWidgetNeitherBlocksNorMoves() {
    var away = Placement(widget: "tasks.list", size: .medium, column: 2, row: 0)
    away.away = 1
    var layout = ownersHome
    layout.placed.insert(away, at: 0)
    #expect(layout.moving("clipboard.history", column: 0, row: 0, available: ownersWidgets)?.placed == [
      away,
      Placement(widget: "shelf.files", size: .medium, column: 2, row: 0),
      Placement(widget: "clipboard.history", size: .large, column: 0, row: 0),
    ])
  }

  /// A place written without `away`, by hand or by a build before it, reads as a widget that shows.
  @Test
  func aPlaceSavedWithoutAwayShows() throws {
    let json = Data(#"{"widget":"clipboard.history","size":"large","column":0,"row":0}"#.utf8)
    let placement = try JSONDecoder().decode(Placement.self, from: json)
    #expect(placement == Placement(widget: "clipboard.history", size: .large, column: 0, row: 0))
    #expect(!placement.isAway)
  }

  // MARK: - The utilities button

  /// A 186 pt notch, the widest the 680 pt window keeps, where it cuts into Home's 624 pt column, whose middle is 312.
  let notch = CGRect(x: 191, y: 0, width: 186, height: 32)

  /// The circle stays inside Home's column, 8 pt from its edges as in its slot: its center 22 pt in. Without a place
  /// it is in its slot, 22 pt from the column's right edge in the middle of the row.
  @Test
  func theButtonStaysInsideTheColumn() {
    #expect(HomeLayout.buttonCenter(nil, notch: nil) == CGPoint(x: 602, y: 26))
    #expect(HomeLayout.buttonCenter(CGPoint(x: -100, y: 200), notch: nil) == CGPoint(x: 212, y: 200))
    #expect(HomeLayout.buttonCenter(CGPoint(x: -400, y: 0), notch: nil) == CGPoint(x: 22, y: 22))
    #expect(HomeLayout.buttonCenter(CGPoint(x: 400, y: 500), notch: nil) == CGPoint(x: 602, y: 418))
    // A drop past an edge settles inside it.
    #expect(HomeLayout.buttonPlace(droppedAt: CGPoint(x: -30, y: 470), notch: nil) == CGPoint(x: -290, y: 418))
  }

  /// A drop under the notch goes to the nearest place 8 pt clear of it: beside it, or below it from its middle.
  @Test
  func aDropUnderTheNotchGoesBesideOrBelowIt() {
    #expect(HomeLayout.buttonPlace(droppedAt: CGPoint(x: 200, y: 20), notch: notch) == CGPoint(x: 169 - 312, y: 22))
    #expect(HomeLayout.buttonPlace(droppedAt: CGPoint(x: 390, y: 30), notch: notch) == CGPoint(x: 399 - 312, y: 30))
    #expect(HomeLayout.buttonPlace(droppedAt: CGPoint(x: 284, y: 10), notch: notch) == CGPoint(x: 284 - 312, y: 54))
    // Without a notch it stays where it was dropped.
    #expect(HomeLayout.buttonPlace(droppedAt: CGPoint(x: 284, y: 22), notch: nil) == CGPoint(x: 284 - 312, y: 22))
  }

  /// A drop whose center lands within 20 pt of the slot's center puts the button back in its slot; so does one past
  /// the column's right edge at the row's height, which settles there.
  @Test
  func aDropNearTheSlotPutsTheButtonBack() {
    #expect(HomeLayout.buttonPlace(droppedAt: CGPoint(x: 602 - 12, y: 26 + 16), notch: nil) == nil)
    #expect(HomeLayout.buttonPlace(droppedAt: CGPoint(x: 602 - 12, y: 26 + 17), notch: nil) == CGPoint(x: 278, y: 43))
    #expect(HomeLayout.buttonPlace(droppedAt: CGPoint(x: 680, y: 30), notch: nil) == nil)
  }

  /// A place that doesn't fit, as one saved at the right edge of a 240 pt notch's 678 pt column shown in the 624 pt
  /// one, shows at the nearest place that does; the place itself doesn't change.
  @Test
  func aPlaceOutOfBoundsOnANarrowerColumnShowsAtTheNearestThatFits() {
    let wideNotch = CGRect(x: 191, y: 0, width: 240, height: 32)
    let place = CGPoint(x: 317, y: 300)
    #expect(HomeLayout.buttonCenter(place, notch: wideNotch) == CGPoint(x: 339 + 317, y: 300))
    #expect(HomeLayout.buttonCenter(place, notch: notch) == CGPoint(x: 602, y: 300))
    // Its slot follows the column's right edge.
    #expect(HomeLayout.buttonCenter(nil, notch: wideNotch) == CGPoint(x: 656, y: 26))
  }

  /// A home.json without the button's place, as builds before it wrote, reads as the button in its slot.
  @Test
  func anOldHomeJSONReadsAsTheButtonInItsSlot() throws {
    let json = Data(
      #"{"notchRow":"timer.timer","placed":[{"widget":"shelf.files","size":"medium","column":0,"row":0}]}"#.utf8
    )
    let layout = try JSONDecoder().decode(HomeLayout.self, from: json)
    #expect(layout == HomeLayout(notchRow: "timer.timer", placed: [ownersHome.placed[0]]))
    #expect(layout.button == nil)
  }

  /// The place goes to home.json and back as it was; in its slot the button writes nothing there.
  @Test
  func theButtonsPlaceMakesARoundTrip() throws {
    var layout = ownersHome
    #expect(!String(decoding: try JSONEncoder().encode(layout), as: UTF8.self).contains("button"))
    layout.button = CGPoint(x: -120, y: 200)
    let data = try JSONEncoder().encode(layout)
    #expect(String(decoding: data, as: UTF8.self).contains(#""button":[-120,200]"#))
    #expect(try JSONDecoder().decode(HomeLayout.self, from: data) == layout)
  }
}
