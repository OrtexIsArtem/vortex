import ComposableArchitecture
import Foundation
import Testing

@testable import VortexPlatform

/// Readings take turns, `readingsAtOnce` at a time: a reading given up ends at once and frees its turn, and one the user
/// waits for takes the next free turn before any waiting in the background. Each test has a queue of its own, so other
/// tests' readings never take its turns.
struct ReadingQueueTests {
  /// A door a reading waits at, holding its turn, until the test opens it.
  final class Door: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func wait() { semaphore.wait() }
    func open() { semaphore.signal() }
  }

  /// Waits until `queue` holds `count` readings, running or waiting.
  func waitUntil(_ queue: ReadingQueue, holds count: Int) async throws {
    for _ in 0..<500 where queue.count != count { try await Task.sleep(for: .milliseconds(10)) }
    try #require(queue.count == count)
  }

  /// One waiting for its turn and given up ends at once, its turn never comes, and the reading before it goes on.
  @Test
  func aReadingGivenUpWhileItWaitsEndsAtOnceAndNeverStarts() async throws {
    let queue = ReadingQueue(width: 1)
    let door = Door()
    let started = LockIsolated<[String]>([])
    let first = Task { try await queue.run(.background) { _ in started.withValue { $0.append("first") }; door.wait(); return "first" } }
    try await waitUntil(queue, holds: 1)
    let second = Task { try await queue.run(.background) { _ in started.withValue { $0.append("second") }; return "second" } }
    try await waitUntil(queue, holds: 2)
    second.cancel()
    await #expect(throws: CancellationError.self) { try await second.value }
    door.open()
    #expect(try await first.value == "first")
    try await waitUntil(queue, holds: 0)
    #expect(started.value == ["first"])
  }

  /// One given up while it reads ends at once with no text, and its turn goes to the next straight away, though the
  /// work it gave up ends only when it next looks.
  @Test
  func aReadingGivenUpWhileItReadsFreesItsTurnAtOnce() async throws {
    let queue = ReadingQueue(width: 1)
    let looking = Door()
    let first = Task {
      try await queue.run(.background) { read in
        // Vision's read, stopped by its cancelled requests, looks once given up.
        while !read.wasGivenUp { usleep(1_000) }
        looking.wait()
        try read.check()
        return "first"
      }
    }
    try await waitUntil(queue, holds: 1)
    let next = Task { try await queue.run(.background) { _ in "next" } }
    try await waitUntil(queue, holds: 2)
    let start = ContinuousClock.now
    first.cancel()
    await #expect(throws: CancellationError.self) { try await first.value }
    #expect(ContinuousClock.now - start < .milliseconds(500))
    looking.open()
    #expect(try await next.value == "next")
  }

  /// With every turn taken and a reading waiting in the background, one the user waits for takes the next free turn.
  @Test
  func anInteractiveReadingOvertakesTheOnesWaitingInTheBackground() async throws {
    let queue = ReadingQueue(width: 1)
    let door = Door()
    let order = LockIsolated<[String]>([])
    func reading(_ name: String, _ urgency: Urgency, waits: Bool = false) -> Task<String, Error> {
      Task {
        try await queue.run(urgency) { _ in
          order.withValue { $0.append(name) }
          if waits { door.wait() }
          return name
        }
      }
    }
    let holding = reading("holding", .background, waits: true)
    try await waitUntil(queue, holds: 1)
    let background = reading("background", .background)
    try await waitUntil(queue, holds: 2)
    let interactive = reading("interactive", .interactive)
    try await waitUntil(queue, holds: 3)
    door.open()
    _ = try await (holding.value, background.value, interactive.value)
    #expect(order.value == ["holding", "interactive", "background"])
  }

  /// A reading keeps nothing after its turn, as the picture it read, which may be a whole screen.
  @Test
  func aReadingKeepsNothingAfterItsTurn() async throws {
    final class Picture: Sendable {}
    let queue = ReadingQueue(width: 1)
    weak var kept: Picture?
    do {
      let picture = Picture()
      kept = picture
      _ = try await queue.run(.background) { _ in withExtendedLifetime(picture) { 1 } }
    }
    try await waitUntil(queue, holds: 0)
    #expect(kept == nil)
  }

  /// A read Vision makes stops when its task is cancelled: the tester's wide picture of small text, which takes a moment
  /// to read whole, ends in `CancellationError` soon after, with no text.
  @Test
  func aVisionReadStopsWhenItsTaskIsCancelled() async throws {
    let picture = try Fixture.image("dense-wide")
    let read = Task { try await TextRecognitionClient.liveValue.recognizeAsWritten(picture) }
    try await Task.sleep(for: .milliseconds(100))
    let start = ContinuousClock.now
    read.cancel()
    await #expect(throws: CancellationError.self) { try await read.value }
    #expect(ContinuousClock.now - start < .milliseconds(500))
  }
}
