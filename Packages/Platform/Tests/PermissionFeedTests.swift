import ComposableArchitecture
import Foundation
import Testing
import VortexCore

@testable import VortexPlatform

/// The live client's scheduling, with a read and a clock of the test's own: nothing here asks macOS.
@Suite(.timeLimit(.minutes(1)))
struct PermissionFeedTests {
  typealias Statuses = [Permission: PermissionStatus]

  static let off: Statuses = [.accessibility: .notGranted]
  static let on: Statuses = [.accessibility: .granted]

  /// Holds reads back until the test lets them go.
  final class Gate: Sendable {
    private let state = LockIsolated<(isOpen: Bool, waiting: [CheckedContinuation<Void, Never>])>((false, []))

    func wait() async {
      await withCheckedContinuation { continuation in
        let goOn = state.withValue { state in
          if state.isOpen { return true }
          state.waiting.append(continuation)
          return false
        }
        if goOn { continuation.resume() }
      }
    }

    func open() {
      let waiting = state.withValue { state in
        state.isOpen = true
        defer { state.waiting = [] }
        return state.waiting
      }
      for continuation in waiting {
        continuation.resume()
      }
    }
  }

  /// Lets the feed's tasks run, so what would happen has happened.
  func settle() async throws {
    try await Task.sleep(for: .milliseconds(100))
  }

  // MARK: Listeners never stay behind

  @Test
  func aConsumerThatStopsLeavesNoListenerHoweverItStops() async {
    let feed = PermissionFeed(clock: ImmediateClock()) { Self.off }
    for _ in 0..<200 {
      let cancelled = Task { for await _ in feed.updates() {} }
      cancelled.cancel()
      await cancelled.value
      #expect(feed.listenerCount == 0)

      let satisfied = Task {
        for await _ in feed.updates() { break }
      }
      await satisfied.value
      #expect(feed.listenerCount == 0)

      _ = feed.updates()
      #expect(feed.listenerCount == 0)
    }
  }

  // MARK: The read loop

  /// A read that finds what the last one found tells nobody.
  @Test
  func listenersHearOnlyChanges() async throws {
    let next = LockIsolated(Self.off)
    let feed = PermissionFeed(clock: ImmediateClock()) { next.value }
    let told = LockIsolated<[Statuses]>([])
    let listener = Task {
      for await statuses in feed.updates() {
        told.withValue { $0.append(statuses) }
      }
    }
    _ = await feed.statuses()
    try await settle()
    _ = await feed.statuses()
    _ = await feed.statuses()
    try await settle()
    next.setValue(Self.on)
    _ = await feed.statuses()
    try await settle()
    #expect(told.value == [Self.off, Self.on])
    listener.cancel()
  }

  /// Wake-ups that come during a read make one more read after it, not one each.
  @Test
  func aBurstOfWakeUpsDuringAReadMakesOneMoreRead() async throws {
    let reads = LockIsolated(0)
    let gate = Gate()
    let (started, didStart) = AsyncStream.makeStream(of: Int.self)
    let feed = PermissionFeed(clock: ImmediateClock()) {
      let read = reads.withValue { $0 += 1; return $0 }
      didStart.yield(read)
      if read == 1 { await gate.wait() }
      return Self.off
    }
    var startedReads = started.makeAsyncIterator()
    feed.wakeUp()
    #expect(await startedReads.next() == 1)
    for _ in 0..<10 {
      feed.wakeUp()
    }
    gate.open()
    #expect(await startedReads.next() == 2)
    try await settle()
    #expect(reads.value == 2)
  }

  @Test
  func aCallerOfStatusesGetsTheReadThatStartsAfterIt() async {
    let reads = LockIsolated(0)
    let feed = PermissionFeed(clock: ImmediateClock()) {
      let read = reads.withValue { $0 += 1; return $0 }
      return read == 1 ? Self.off : Self.on
    }
    #expect(await feed.statuses() == Self.off)
    #expect(await feed.statuses() == Self.on)
  }

  /// A listener that comes later, such as a second window, doesn't wait for a change.
  @Test
  func aLateListenerGetsTheLastStatusesAtOnce() async {
    let reads = LockIsolated(0)
    let gate = Gate()
    let feed = PermissionFeed(clock: ImmediateClock()) {
      let read = reads.withValue { $0 += 1; return $0 }
      // Every read after the first is held back: the late listener can't be served by one.
      if read > 1 { await gate.wait() }
      return Self.on
    }
    var first = feed.updates().makeAsyncIterator()
    #expect(await first.next() == Self.on)
    var late = feed.updates().makeAsyncIterator()
    #expect(await late.next() == Self.on)
    gate.open()
  }

  @Test
  func itReadsEverySecondOnlyWhileFrequentChecksAreOn() async throws {
    let clock = TestClock()
    let reads = LockIsolated(0)
    let (started, didStart) = AsyncStream.makeStream(of: Int.self)
    let feed = PermissionFeed(clock: clock) {
      didStart.yield(reads.withValue { $0 += 1; return $0 })
      return Self.off
    }
    var startedReads = started.makeAsyncIterator()

    await clock.advance(by: .seconds(5))
    try await settle()
    #expect(reads.value == 0)

    feed.setFrequentChecks(true)
    #expect(await startedReads.next() == 1)
    await Task.megaYield()
    await clock.advance(by: .seconds(1))
    #expect(await startedReads.next() == 2)
    await Task.megaYield()
    await clock.advance(by: .seconds(1))
    #expect(await startedReads.next() == 3)

    feed.setFrequentChecks(false)
    await clock.advance(by: .seconds(5))
    try await settle()
    #expect(reads.value == 3)
  }

  /// Accessibility's own signal comes before macOS has written the change: the read waits 250 ms.
  @Test
  func aDelayedWakeUpReadsOnlyAfterItsDelay() async throws {
    let clock = TestClock()
    let reads = LockIsolated(0)
    let feed = PermissionFeed(clock: clock) {
      reads.withValue { $0 += 1 }
      return Self.off
    }
    feed.wakeUp(after: .milliseconds(250))
    await Task.megaYield()
    await clock.advance(by: .milliseconds(249))
    try await settle()
    #expect(reads.value == 0)
    await clock.advance(by: .milliseconds(1))
    try await settle()
    #expect(reads.value == 1)
  }
}
