import ComposableArchitecture
import Testing
import VortexCore
import VortexPlatform

@testable import VortexShell

@MainActor
struct KeyboardCleaningFeatureTests {
  /// The keyboard held (true) and let go (false), in order.
  let holds = LockIsolated<[Bool]>([])
  let unlocks = LockIsolated(0)

  func makeStore(accessibility: PermissionStatus?) -> TestStoreOf<KeyboardCleaningFeature> {
    @Shared(.permissionStatuses) var statuses
    $statuses.withLock { $0 = accessibility.map { [.accessibility: $0] } ?? [:] }
    // Calls nobody expects — `lock` without access, among them — fail the test.
    return TestStore(initialState: KeyboardCleaningFeature.State()) {
      KeyboardCleaningFeature()
    } withDependencies: {
      $0.windowClient.holdKeyboard = { [holds] isHeld in holds.withValue { $0.append(isHeld) } }
      $0.keyboardLockClient.unlock = { [unlocks] in unlocks.withValue { $0 += 1 } }
    }
  }

  /// Without Accessibility the click opens its page and locks nothing; macOS is never asked.
  @Test
  func withoutAccessTheClickOpensThePageAndLocksNothing() async {
    let store = makeStore(accessibility: .notGranted)
    await store.send(.startTapped)
    await store.receive(\.delegate, .openPage(lockRefused: false))
    #expect(holds.value.isEmpty)
  }

  /// A tap macOS refuses while the status reads granted opens the page that says to turn the switch off and on again.
  @Test
  func aTapMacOSRefusesLetsTheKeyboardGoAndOpensThePageThatSaysToFlipTheSwitch() async {
    let store = makeStore(accessibility: .granted)
    store.dependencies.keyboardLockClient.lock = { false }
    await store.send(.startTapped) { $0.isLocked = true }
    await store.receive(\.lockFailed) { $0.isLocked = false }
    await store.receive(\.delegate, .openPage(lockRefused: true))
    #expect(holds.value == [true, false])
    #expect(unlocks.value == 1)
  }

  /// Before the first read the lock is tried; a refusal opens the ordinary page.
  @Test
  func aRefusalBeforeTheFirstReadOpensTheOrdinaryPage() async {
    let store = makeStore(accessibility: nil)
    store.dependencies.keyboardLockClient.lock = { false }
    await store.send(.startTapped) { $0.isLocked = true }
    await store.receive(\.lockFailed) { $0.isLocked = false }
    await store.receive(\.delegate, .openPage(lockRefused: false))
  }

  /// Accessibility lost during the lock: the tap goes at once and no page opens.
  @Test
  func losingAccessDuringTheLockEndsItWithoutAPage() async {
    let store = makeStore(accessibility: .granted)
    store.dependencies.keyboardLockClient.lock = { true }
    await store.send(.startTapped) { $0.isLocked = true }
    await store.send(.accessLost) { $0.isLocked = false }
    await store.finish()
    #expect(unlocks.value == 1)
    #expect(holds.value == [true, false])
  }
}
