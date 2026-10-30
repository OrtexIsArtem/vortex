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
}
