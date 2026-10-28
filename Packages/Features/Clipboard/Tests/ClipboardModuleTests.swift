import Testing
import VortexCore

@testable import FeatureClipboard

@MainActor
struct ClipboardModuleTests {
  /// The history reads other apps' copies (S33).
  @Test
  func theClipboardNeedsPasteFromOtherApps() {
    #expect(ClipboardModule.permissionNeeds.map(\.permission) == [.pasteboard])
    #expect(ClipboardModule.descriptor.permissionNeeds == ClipboardModule.permissionNeeds)
  }
}
