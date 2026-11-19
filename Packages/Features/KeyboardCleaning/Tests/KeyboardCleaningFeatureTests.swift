import ComposableArchitecture
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureKeyboardCleaning

@MainActor
struct KeyboardCleaningFeatureTests {
  let unlocks = LockIsolated(0)
  /// The pages asked for: "page <permission>" and "refused <permission>".
  let pages = LockIsolated<[String]>([])

  /// The lock screen, as the feature puts it up over the window.
  static let lockScreen = WindowCover(feature: "keyboard", holdsKeyboard: true)

  func makeStore(accessibility: PermissionStatus?) -> TestStoreOf<KeyboardCleaningFeature> {
    @Shared(.permissionStatuses) var statuses
    $statuses.withLock { $0 = accessibility.map { [.accessibility: $0] } ?? [:] }
    // Calls nobody expects — `lock` without access, among them — fail the test.
    return TestStore(initialState: KeyboardCleaningFeature.State()) {
      KeyboardCleaningFeature()
    } withDependencies: {
      $0.keyboardLockClient.unlock = { [unlocks] in unlocks.withValue { $0 += 1 } }
      $0.keyboardLockClient.layout = { .ansi }
      $0.keyboardLockClient.presses = { .never }
      $0.permissionPage.open = { [pages] permission in pages.withValue { $0.append("page \(permission)") } }
      $0.permissionPage.openRefused = { [pages] permission in pages.withValue { $0.append("refused \(permission)") } }
    }
  }

  /// Without Accessibility the click opens its page and locks nothing: no cover, and macOS is never asked.
  @Test
  func withoutAccessTheClickOpensThePageAndLocksNothing() async {
    let store = makeStore(accessibility: .notGranted)
    await store.send(.startTapped)
    await store.finish()
    #expect(pages.value == ["page accessibility"])
    #expect(store.state.cover == nil)
  }

  /// The lock puts the lock screen over the window, with Vortex holding the keyboard; «Turn the keyboard back on» lets
  /// the keys go and takes the cover down, which closes the window.
  @Test
  func theLockCoversTheWindowUntilTheKeyboardIsBackOn() async {
    let store = makeStore(accessibility: .granted)
    store.dependencies.keyboardLockClient.lock = { true }
    await store.send(.startTapped) {
      $0.isLocked = true
      $0.$cover.withLock { $0 = Self.lockScreen }
    }
    await store.send(.stopTapped) {
      $0.isLocked = false
      $0.$cover.withLock { $0 = nil }
    }
    await store.finish()
    #expect(unlocks.value == 1)
    #expect(pages.value.isEmpty)
  }

  /// A tap macOS refuses while the status reads granted takes the cover down and opens the page that says to turn the
  /// switch off and on again.
  @Test
  func aTapMacOSRefusesLetsTheKeyboardGoAndOpensThePageThatSaysToFlipTheSwitch() async {
    let store = makeStore(accessibility: .granted)
    store.dependencies.keyboardLockClient.lock = { false }
    await store.send(.startTapped) {
      $0.isLocked = true
      $0.$cover.withLock { $0 = Self.lockScreen }
    }
    await store.receive(\.lockFailed) {
      $0.isLocked = false
      $0.$cover.withLock { $0 = nil }
    }
    await store.finish()
    #expect(pages.value == ["refused accessibility"])
    #expect(unlocks.value == 1)
  }

  /// Before the first read the lock is tried; a refusal opens the ordinary page.
  @Test
  func aRefusalBeforeTheFirstReadOpensTheOrdinaryPage() async {
    let store = makeStore(accessibility: nil)
    store.dependencies.keyboardLockClient.lock = { false }
    await store.send(.startTapped) {
      $0.isLocked = true
      $0.$cover.withLock { $0 = Self.lockScreen }
    }
    await store.receive(\.lockFailed) {
      $0.isLocked = false
      $0.$cover.withLock { $0 = nil }
    }
    await store.finish()
    #expect(pages.value == ["page accessibility"])
  }

  /// Accessibility lost during the lock ends it at once: the tap goes, the cover with it, and no page opens.
  @Test
  func losingAccessDuringTheLockEndsItWithoutAPage() async {
    let store = makeStore(accessibility: .granted)
    store.dependencies.keyboardLockClient.lock = { true }
    await store.send(.startTapped) {
      $0.isLocked = true
      $0.$cover.withLock { $0 = Self.lockScreen }
    }
    @Shared(.permissionStatuses) var statuses
    $statuses.withLock { $0 = [.accessibility: .notGranted] }
    await store.receive(\.accessLost) {
      $0.isLocked = false
      $0.$cover.withLock { $0 = nil }
    }
    await store.finish()
    #expect(unlocks.value == 1)
    #expect(pages.value.isEmpty)
  }

  /// The utility stopping, as Remove stops it, ends a lock under way as «Turn the keyboard back on» does; with none, it
  /// changes nothing.
  @Test
  func stoppingTheUtilityEndsALockUnderWay() async {
    let store = makeStore(accessibility: .granted)
    store.dependencies.keyboardLockClient.lock = { true }
    await store.send(.stopped)
    await store.send(.startTapped) {
      $0.isLocked = true
      $0.$cover.withLock { $0 = Self.lockScreen }
    }
    await store.send(.stopped) {
      $0.isLocked = false
      $0.$cover.withLock { $0 = nil }
    }
    await store.finish()
    #expect(unlocks.value == 1)
  }

  /// «Turn the keyboard back on» while Vortex is still getting ready to take the keys, its unlock done first: the start
  /// never locks after it.
  @Test
  func aLockEndedBeforeTheTapNeverTakesTheKeysAfterwards() async {
    let store = makeStore(accessibility: .granted)
    let calls = LockIsolated<[String]>([])
    let (arrived, unlocked) = (Arrival(), Latch())
    store.dependencies.keyboardLockClient.presses = {
      calls.withValue { $0.append("listen") }
      arrived.signal()
      await unlocked.wait()
      return .never
    }
    store.dependencies.keyboardLockClient.lock = {
      calls.withValue { $0.append("lock") }
      return true
    }
    store.dependencies.keyboardLockClient.unlock = {
      calls.withValue { $0.append("unlock") }
      unlocked.open()
    }
    await store.send(.startTapped) {
      $0.isLocked = true
      $0.$cover.withLock { $0 = Self.lockScreen }
    }
    await arrived.wait()
    await store.send(.stopTapped) {
      $0.isLocked = false
      $0.$cover.withLock { $0 = nil }
    }
    await store.finish()
    #expect(!calls.value.contains("lock"))
    #expect(calls.value == ["listen", "unlock"])
  }

  /// «Turn the keyboard back on» while macOS is taking the keys, its unlock done before the lock returns: the keys go
  /// once more after the lock.
  @Test
  func aLockEndedWhileMacOSTakesTheKeysLetsThemGoAfter() async {
    let store = makeStore(accessibility: .granted)
    let calls = LockIsolated<[String]>([])
    let (arrived, unlocked) = (Arrival(), Latch())
    store.dependencies.keyboardLockClient.lock = {
      arrived.signal()
      await unlocked.wait()
      calls.withValue { $0.append("locked") }
      return true
    }
    store.dependencies.keyboardLockClient.unlock = {
      calls.withValue { $0.append("unlock") }
      unlocked.open()
    }
    await store.send(.startTapped) {
      $0.isLocked = true
      $0.$cover.withLock { $0 = Self.lockScreen }
    }
    await arrived.wait()
    await store.send(.stopTapped) {
      $0.isLocked = false
      $0.$cover.withLock { $0 = nil }
    }
    await store.finish()
    #expect(calls.value == ["unlock", "locked", "unlock"])
  }

  /// A key pressed as the tap goes live, before `lock` even returns, still counts: the lock listens first.
  @Test
  func aKeyPressedAsTheLockBeginsCounts() async {
    let store = makeStore(accessibility: .granted)
    // As the live tap does: a key reaches only who listens when it goes down.
    let listeners = LockIsolated<[AsyncStream<KeyboardKey>.Continuation]>([])
    store.dependencies.keyboardLockClient.presses = {
      let (stream, continuation) = AsyncStream.makeStream(of: KeyboardKey.self)
      listeners.withValue { $0.append(continuation) }
      return stream
    }
    store.dependencies.keyboardLockClient.lock = {
      listeners.value.forEach { $0.yield(.escape) }
      return true
    }
    await store.send(.startTapped) {
      $0.isLocked = true
      $0.$cover.withLock { $0 = Self.lockScreen }
    }
    await store.receive(\.keyPressed, .escape) { $0.presses[.escape] = 1 }
    await store.send(.stopTapped) {
      $0.isLocked = false
      $0.presses = [:]
      $0.$cover.withLock { $0 = nil }
    }
    await store.finish()
  }

  // MARK: - Washing

  /// Each press washes its key a step; the third washes it clean, and more keep it there. A key that got past the lock
  /// reaches the same presses (the shell hands it to `KeyboardLockClient.reportPassed`).
  @Test
  func eachPressWashesItsKeyAStepUpToCleanAtTheThird() async {
    let store = makeStore(accessibility: .granted)
    let (presses, keyboard) = AsyncStream.makeStream(of: KeyboardKey.self)
    store.dependencies.keyboardLockClient.lock = { true }
    store.dependencies.keyboardLockClient.presses = { presses }
    await store.send(.startTapped) {
      $0.isLocked = true
      $0.$cover.withLock { $0 = Self.lockScreen }
    }
    #expect(store.state.washes(of: .a) == 0)

    for count in 1...4 {
      keyboard.yield(.a)
      await store.receive(\.keyPressed, .a) { $0.presses[.a] = count }
    }
    keyboard.yield(.f1)
    await store.receive(\.keyPressed, .f1) { $0.presses[.f1] = 1 }
    #expect(store.state.washes(of: .a) == 3)
    #expect(store.state.washes(of: .f1) == 1)
    #expect(store.state.washes(of: .s) == 0)

    await store.send(.stopTapped) {
      $0.isLocked = false
      $0.presses = [:]
      $0.$cover.withLock { $0 = nil }
    }
    await store.finish()
  }

  /// The lock ends: it stops listening, and nothing pressed outlives it; the next lock starts every key dirty and reads
  /// the keyboard's layout again.
  @Test
  func afterTheLockNoKeyCountsAndTheNextOneStartsDirty() async {
    let store = makeStore(accessibility: .granted)
    let listening = LockIsolated(0)
    let (presses, keyboard) = AsyncStream.makeStream(of: KeyboardKey.self)
    store.dependencies.keyboardLockClient.lock = { true }
    store.dependencies.keyboardLockClient.presses = {
      listening.withValue { $0 += 1 }
      return presses
    }
    await store.send(.startTapped) {
      $0.isLocked = true
      $0.$cover.withLock { $0 = Self.lockScreen }
    }
    keyboard.yield(.space)
    await store.receive(\.keyPressed, .space) { $0.presses[.space] = 1 }
    await store.send(.stopTapped) {
      $0.isLocked = false
      $0.presses = [:]
      $0.$cover.withLock { $0 = nil }
    }
    await store.finish()
    // The loop that listened is gone: a key now reaches nobody, and one sent anyway changes nothing.
    keyboard.yield(.space)
    await store.send(.keyPressed(.space))

    store.dependencies.keyboardLockClient.layout = { .iso }
    store.dependencies.keyboardLockClient.presses = { .never }
    await store.send(.startTapped) {
      $0.isLocked = true
      $0.layout = .iso
      $0.$cover.withLock { $0 = Self.lockScreen }
    }
    #expect(store.state.washes(of: .space) == 0)
    #expect(listening.value == 1)
    await store.send(.stopTapped) {
      $0.isLocked = false
      $0.$cover.withLock { $0 = nil }
    }
    await store.finish()
  }
}

/// Tells the test that a dependency's call has arrived.
private final class Arrival: Sendable {
  private let arrivals = AsyncStream.makeStream(of: Void.self)

  func signal() {
    arrivals.continuation.yield()
  }

  func wait() async {
    for await _ in arrivals.stream { return }
  }
}

/// Holds a dependency's call until another call opens it, even after its task is cancelled, as a call into macOS goes
/// on regardless.
private final class Latch: Sendable {
  private let state = LockIsolated<(isOpen: Bool, waiter: CheckedContinuation<Void, Never>?)>((false, nil))

  func wait() async {
    await withCheckedContinuation { continuation in
      let isOpen = state.withValue { state in
        if !state.isOpen { state.waiter = continuation }
        return state.isOpen
      }
      if isOpen { continuation.resume() }
    }
  }

  func open() {
    let waiter = state.withValue { state in
      state.isOpen = true
      defer { state.waiter = nil }
      return state.waiter
    }
    waiter?.resume()
  }
}
