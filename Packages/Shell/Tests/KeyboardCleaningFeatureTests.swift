import ComposableArchitecture
import CoreGraphics
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
      $0.keyboardLockClient.layout = { .ansi }
      $0.keyboardLockClient.presses = { .never }
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

  /// «Turn the keyboard back on» while Vortex is still taking the keyboard, its unlock done first: the start never
  /// locks after it, and lets the keyboard go.
  @Test
  func aLockEndedBeforeTheTapNeverTakesTheKeysAfterwards() async {
    let store = makeStore(accessibility: .granted)
    let calls = LockIsolated<[String]>([])
    let (arrived, unlocked) = (Arrival(), Latch())
    store.dependencies.windowClient.holdKeyboard = { isHeld in
      calls.withValue { $0.append("hold \(isHeld)") }
      guard isHeld else { return }
      arrived.signal()
      await unlocked.wait()
    }
    store.dependencies.keyboardLockClient.lock = {
      calls.withValue { $0.append("lock") }
      return true
    }
    store.dependencies.keyboardLockClient.unlock = {
      calls.withValue { $0.append("unlock") }
      unlocked.open()
    }
    await store.send(.startTapped) { $0.isLocked = true }
    await arrived.wait()
    await store.send(.stopTapped) { $0.isLocked = false }
    await store.finish()
    #expect(!calls.value.contains("lock"))
    #expect(calls.value.last { $0.hasPrefix("hold") } == "hold false")
  }

  /// «Turn the keyboard back on» while macOS is taking the keys, its unlock done before the lock returns: the keys go
  /// once more after the lock.
  @Test
  func aLockEndedWhileMacOSTakesTheKeysLetsThemGoAfter() async {
    let store = makeStore(accessibility: .granted)
    let calls = LockIsolated<[String]>([])
    let (arrived, unlocked) = (Arrival(), Latch())
    store.dependencies.windowClient.holdKeyboard = { isHeld in calls.withValue { $0.append("hold \(isHeld)") } }
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
    await store.send(.startTapped) { $0.isLocked = true }
    await arrived.wait()
    await store.send(.stopTapped) { $0.isLocked = false }
    await store.finish()
    #expect(calls.value.filter { $0 == "locked" || $0 == "unlock" } == ["unlock", "locked", "unlock"])
    #expect(calls.value.last { $0.hasPrefix("hold") } == "hold false")
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
    await store.send(.startTapped) { $0.isLocked = true }
    await store.receive(\.keyPressed, .escape) { $0.presses[.escape] = 1 }
    await store.send(.stopTapped) {
      $0.isLocked = false
      $0.presses = [:]
    }
    await store.finish()
  }

  // MARK: - Washing

  /// Each press washes its key a step; the third washes it clean, and more keep it there.
  @Test
  func eachPressWashesItsKeyAStepUpToCleanAtTheThird() async {
    let store = makeStore(accessibility: .granted)
    let (presses, keyboard) = AsyncStream.makeStream(of: KeyboardKey.self)
    store.dependencies.keyboardLockClient.lock = { true }
    store.dependencies.keyboardLockClient.presses = { presses }
    await store.send(.startTapped) { $0.isLocked = true }
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
    await store.send(.startTapped) { $0.isLocked = true }
    keyboard.yield(.space)
    await store.receive(\.keyPressed, .space) { $0.presses[.space] = 1 }
    await store.send(.stopTapped) {
      $0.isLocked = false
      $0.presses = [:]
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
    }
    #expect(store.state.washes(of: .space) == 0)
    #expect(listening.value == 1)
    await store.send(.stopTapped) { $0.isLocked = false }
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

/// The drawn keyboard: every key of the board has a key code of its own.
struct KeyboardBoardTests {
  /// The lock screen's: the window less its margins.
  static let metrics = KeyboardBoard.Metrics(width: 624)

  @Test(arguments: KeyboardLayout.allCases)
  func everyDrawnKeyButTouchIDHasAKeyCodeOfItsOwn(layout: KeyboardLayout) {
    let board = KeyboardBoard(layout, metrics: Self.metrics)
    let keys = board.caps.compactMap(\.key)
    #expect(Set(keys).count == keys.count)
    #expect(board.caps.filter { $0.key == nil }.map(\.shape) == [.touchID])
    #expect(Set(board.caps.map(\.id)).count == board.caps.count)
  }

  /// ANSI, also for JIS, draws every key but §; ISO draws them all, § top left and ` left of Z.
  @Test
  func ansiDrawsEveryKeyButTheSectionAndISOThemAll() throws {
    let ansi = KeyboardBoard(.ansi, metrics: Self.metrics)
    #expect(Set(ansi.caps.compactMap(\.key)) == Set(KeyboardKey.allCases).subtracting([.section]))
    #expect(KeyboardBoard(.jis, metrics: Self.metrics) == ansi)
    let iso = KeyboardBoard(.iso, metrics: Self.metrics)
    #expect(Set(iso.caps.compactMap(\.key)) == Set(KeyboardKey.allCases))

    func frame(_ key: KeyboardKey, on board: KeyboardBoard) throws -> CGRect {
      try #require(board.caps.first { $0.key == key }).frame
    }
    // Top left of the digits: ` on ANSI, § on ISO, where ` sits left of Z.
    let (ansiGrave, ansiDigit1) = try (frame(.grave, on: ansi), frame(.digit1, on: ansi))
    let (section, grave, z) = try (frame(.section, on: iso), frame(.grave, on: iso), frame(.z, on: iso))
    let (shift, ansiShift) = try (frame(.leftShift, on: iso), frame(.leftShift, on: ansi))
    #expect(ansiGrave.minY == ansiDigit1.minY)
    #expect(section == ansiGrave)
    #expect(grave.minY == z.minY && grave.maxX < z.minX)
    #expect(shift.width < ansiShift.width)
    // ISO's Return comes down over the home row, right of \.
    let tall = try #require(iso.caps.first { $0.key == .return })
    let (p, l, backslash) = try (frame(.p, on: iso), frame(.l, on: iso), frame(.backslash, on: iso))
    #expect(tall.frame.minY == p.minY && tall.frame.maxY == l.maxY)
    #expect(backslash.minY == l.minY)
    guard case let .tallReturn(lowerWidth, _) = tall.shape else {
      Issue.record("ISO's Return is not tall")
      return
    }
    #expect(tall.frame.maxX - lowerWidth > backslash.maxX)
  }

  /// Every row is 15 units and fills the board from edge to edge, keys never overlap, and the function row is the
  /// short one, as on a MacBook.
  @Test(arguments: [KeyboardLayout.ansi, .iso])
  func rowsFillTheBoardAndKeysNeverOverlap(layout: KeyboardLayout) {
    let rows = layout == .iso ? KeyboardBoard.isoRows : KeyboardBoard.ansiRows
    #expect(rows.map { $0.map(\.units).reduce(0, +) } == Array(repeating: KeyboardBoard.rowUnits, count: 6))
    let board = KeyboardBoard(layout, metrics: Self.metrics)
    let metrics = Self.metrics
    var top = metrics.padding
    for height in [metrics.shortHeight] + Array(repeating: metrics.keyHeight, count: 5) {
      let row = board.caps.filter { $0.frame.intersects(CGRect(x: 0, y: top, width: board.size.width, height: height)) }
      #expect(abs((row.map(\.frame.minX).min() ?? 0) - metrics.padding) < 0.01)
      #expect(abs((row.map(\.frame.maxX).max() ?? 0) - (board.size.width - metrics.padding)) < 0.01)
      top += height + metrics.gap
    }
    #expect(abs(top - metrics.gap + metrics.padding - board.size.height) < 0.01)
    let parts = board.caps.flatMap { cap -> [CGRect] in
      guard case let .tallReturn(lowerWidth, upperHeight) = cap.shape else { return [cap.frame] }
      let (upper, lower) = cap.frame.divided(atDistance: upperHeight, from: .minYEdge)
      return [upper, CGRect(x: cap.frame.maxX - lowerWidth, y: lower.minY, width: lowerWidth, height: lower.height)]
    }
    for (index, part) in parts.enumerated() {
      for other in parts[(index + 1)...] {
        #expect(!part.insetBy(dx: 0.01, dy: 0.01).intersects(other))
      }
    }
    #expect(board.caps.filter(\.isShort).map(\.label) == ["esc"] + (1...12).map { "F\($0)" } + [""])
  }
}
