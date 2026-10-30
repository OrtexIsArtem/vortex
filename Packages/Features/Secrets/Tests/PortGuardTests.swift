import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureSecrets

/// A QA run never serves on the user's port, and the place QA seeds its own port stays where it is.
@MainActor
struct PortGuardTests {
  /// QA's bootstrap writes `port` into DataFolder/secrets.json before Keys starts: both names are pinned.
  @Test
  func secretsJSONAndItsPortKeyArePinned() throws {
    #expect(SecretsSettings.fileName == "secrets.json")
    let decoded = try JSONDecoder().decode(SecretsSettings.self, from: Data(#"{"port": 50123}"#.utf8))
    #expect(decoded.port == 50123)
    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]
    #expect(encoded?["port"] as? Int == 50123)
  }

  @Test
  func outsideQANoPortIsTaken() {
    #expect(SecretsFeature.qaTakenPorts.isEmpty)
  }

  @Test
  func aTakenPortIsNeverChosenNorServed() async {
    let served = LockIsolated<[Int]>([])
    var state = SecretsFeature.State()
    state.takenPorts = [SecretsSettings.defaultPort]
    state.$settings.withLock { $0.port = 50123 }
    state.isEnabled = true
    state.token = "token"
    let store = TestStore(initialState: state) {
      SecretsFeature()
    } withDependencies: {
      $0.mcpServer.serve = { [served] port, _ in
        served.withValue { $0.append(port) }
        return AsyncStream { _ in }
      }
    }
    store.exhaustivity = .off
    // From Settings: refused, the port stays.
    await store.send(.portChanged(SecretsSettings.defaultPort))
    #expect(store.state.settings.port == 50123)
    #expect(served.value.isEmpty)

    // Already in the settings, however it got there: not served, and the status says why.
    store.state.$settings.withLock { $0.port = SecretsSettings.defaultPort }
    await store.send(.tokenReady("token"))
    await store.receive(\.server.failed)
    #expect(served.value.isEmpty)
    guard case .failed = store.state.server else {
      Issue.record("The server should be failed, not \(store.state.server)")
      return
    }
  }
}
