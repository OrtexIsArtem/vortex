import Testing
import VortexCore

@testable import FeatureShelf

@MainActor
struct ShelfModuleTests {
  /// The shelf's files widget prefers the large size, which Home's first layout takes, and also fits a medium or a
  /// wide one.
  @Test
  func theFilesWidgetIsLargeMediumOrWide() {
    let widgets = ShelfModule.makeHomeWidgets()
    #expect(HomeWidget.problems(widgets, feature: ShelfModule.id).isEmpty)
    #expect(widgets.map(\.id) == ["shelf.files"])
    #expect(widgets.first?.place == .grid([.large, .medium, .wide]))
  }
}
