import ComposableArchitecture
import Testing
import VortexPlatform

@testable import VortexShell

@MainActor
struct KeyboardCleaningFeatureTests {
  /// The keyboard held (true) and let go (false), in order.
  let holds = LockIsolated<[Bool]>([])
  let accessRequests = LockIsolated(0)

  func makeStore(hasAccess: Bool) -> TestStoreOf<KeyboardCleaningFeature> {
    // Calls nobody expects — `lock` without access, among them — fail the test.
    TestStore(initialState: KeyboardCleaningFeature.State()) {
      KeyboardCleaningFeature()
    } withDependencies: {
      $0.keyboardLockClient.hasAccess = { hasAccess }
      $0.keyboardLockClient.requestAccess = { [accessRequests] in accessRequests.withValue { $0 += 1 } }
      $0.windowClient.holdKeyboard = { [holds] isHeld in holds.withValue { $0.append(isHeld) } }
    }
  }

  @Test
  func withoutAccessTheClickAsksForItAndLocksNothing() async {
    let store = makeStore(hasAccess: false)
    await store.send(.startTapped)
    await store.finish()
    #expect(accessRequests.value == 1)
    #expect(holds.value.isEmpty)
  }

  @Test
  func aTapMacOSRefusesLetsTheKeyboardGoAndAsksForAccess() async {
    let store = makeStore(hasAccess: true)
    store.dependencies.keyboardLockClient.lock = { false }
    store.dependencies.keyboardLockClient.unlock = {}
    await store.send(.startTapped) { $0.isLocked = true }
    await store.receive(\.lockFailed) { $0.isLocked = false }
    await store.finish()
    #expect(holds.value == [true, false])
    #expect(accessRequests.value == 1)
  }
}
