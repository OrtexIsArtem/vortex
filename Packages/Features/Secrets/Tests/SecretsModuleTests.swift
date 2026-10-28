import Testing
import VortexCore

@testable import FeatureSecrets

@MainActor
struct SecretsModuleTests {
  /// Claude's key requests show as notifications while the window is closed (S33).
  @Test
  func keysNeedNotifications() {
    #expect(SecretsModule.permissionNeeds.map(\.permission) == [.notifications])
    #expect(SecretsModule.descriptor.permissionNeeds == SecretsModule.permissionNeeds)
  }
}
