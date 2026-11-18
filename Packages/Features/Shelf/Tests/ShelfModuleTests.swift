import Testing
import VortexCore

@testable import FeatureShelf

@MainActor
struct ShelfModuleTests {
  /// The shelf's files widget is medium or wide.
  @Test
  func theFilesWidgetIsMediumOrWide() {
    let widgets = ShelfModule.makeHomeWidgets()
    #expect(HomeWidget.problems(widgets, feature: ShelfModule.id).isEmpty)
    #expect(widgets.map(\.id) == ["shelf.files"])
    #expect(widgets.first?.place == .grid([.medium, .wide]))
  }
}
