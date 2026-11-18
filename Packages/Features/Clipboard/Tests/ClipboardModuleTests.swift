import Testing
import VortexCore

@testable import FeatureClipboard

@MainActor
struct ClipboardModuleTests {
  /// The history reads other apps' copies.
  @Test
  func theClipboardNeedsPasteFromOtherApps() {
    #expect(ClipboardModule.permissionNeeds.map(\.permission) == [.pasteboard])
    #expect(ClipboardModule.descriptor.permissionNeeds == ClipboardModule.permissionNeeds)
  }

  /// The history widget prefers the large size and also fits a medium one.
  @Test
  func theHistoryWidgetIsLargeOrMedium() {
    let widgets = ClipboardModule.makeHomeWidgets()
    #expect(HomeWidget.problems(widgets, feature: ClipboardModule.id).isEmpty)
    #expect(widgets.map(\.id) == ["clipboard.history"])
    #expect(widgets.first?.place == .grid([.large, .medium]))
  }

}
