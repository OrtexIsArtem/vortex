import SwiftUI
import Testing
import VortexCore

@testable import FeatureHome

@MainActor
struct HomeLayoutTests {
  func widget(_ id: FeatureID, _ slot: HomeSlot) -> HomeWidget {
    HomeWidget(id: id, slot: slot, view: EmptyView())
  }

  @Test
  func theFirstHeaderWidgetTakesTheRowNextToTheNotch() {
    let layout = HomeLayout([widget("timer", .header), widget("clock", .header), widget("shelf", .dock)])
    #expect(layout.header?.id == "timer")
  }

  @Test
  func middleAndDockKeepSidebarOrder() {
    let layout = HomeLayout([
      widget("clipboard", .dock), widget("tasks", .main), widget("shelf", .dock), widget("notes", .main),
    ])
    #expect(layout.main.map(\.id) == ["tasks", "notes"])
    #expect(layout.dock.map(\.id) == ["clipboard", "shelf"])
  }

  @Test
  func theDockFillsHomeUntilSomethingIsInTheMiddle() {
    #expect(HomeLayout([widget("shelf", .dock)]).dockHeight == nil)
    #expect(HomeLayout([widget("shelf", .dock), widget("tasks", .main)]).dockHeight == HomeLayout.fixedDockHeight)
  }

  @Test
  func noWidgetsMeansAnEmptyHome() {
    #expect(HomeLayout([]).isEmpty)
    #expect(!HomeLayout([widget("timer", .header)]).isEmpty)
  }
}
