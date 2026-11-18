import SwiftUI
import Testing

@testable import VortexCore

/// The grid Home lays widgets out on, and the rules a feature's widgets follow.
@MainActor
struct HomeWidgetTests {
  @Test
  func theFiveSizesCoverTheirCells() {
    #expect(HomeWidgetSize.small.points == CGSize(width: 143, height: 182))
    #expect(HomeWidgetSize.medium.points == CGSize(width: 298, height: 182))
    #expect(HomeWidgetSize.wide.points == CGSize(width: 608, height: 182))
    #expect(HomeWidgetSize.large.points == CGSize(width: 298, height: 376))
    #expect(HomeWidgetSize.full.points == CGSize(width: 608, height: 376))
    #expect(HomeWidgetSize.allCases.map(\.label) == ["1×1", "2×1", "4×1", "2×2", "4×2"])
  }

  /// Frames are in the area under the notch row, the tab's own width (the sidebar not counted).
  @Test
  func gridFramesFollowTheCells() {
    #expect(HomeGrid.frame(column: 2, row: 1, size: .small) == CGRect(x: 318, y: 194, width: 143, height: 182))
    #expect(HomeGrid.frame(column: 0, row: 0, size: .full) == CGRect(x: 8, y: 0, width: 608, height: 376))
  }

  @Test
  func aFeatureOffersAtMostTwoWidgetsOfOneToThreeSizes() {
    func widget(_ id: String, _ place: HomeWidgetPlace) -> HomeWidget {
      HomeWidget(id: id, feature: "clock", title: "Clock", place: place, view: EmptyView())
    }
    #expect(HomeWidget.problems([widget("clock.face", .grid([.small, .medium]))], feature: "clock").isEmpty)
    #expect(HomeWidget.problems([widget("clock.row", .notchRow), widget("clock.face", .grid([.large]))], feature: "clock").isEmpty)
    // Three widgets, no size, four sizes, a size twice, another feature's id, an id twice.
    let three = ["clock.a", "clock.b", "clock.c"].map { widget($0, .grid([.small])) }
    #expect(!HomeWidget.problems(three, feature: "clock").isEmpty)
    #expect(!HomeWidget.problems([widget("clock.a", .grid([]))], feature: "clock").isEmpty)
    #expect(!HomeWidget.problems([widget("clock.a", .grid([.small, .medium, .wide, .large]))], feature: "clock").isEmpty)
    #expect(!HomeWidget.problems([widget("clock.a", .grid([.small, .small]))], feature: "clock").isEmpty)
    #expect(!HomeWidget.problems([widget("timer.a", .grid([.small]))], feature: "clock").isEmpty)
    #expect(!HomeWidget.problems([widget("clock.a", .grid([.small])), widget("clock.a", .notchRow)], feature: "clock").isEmpty)
  }
}
