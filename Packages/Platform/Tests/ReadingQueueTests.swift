import ComposableArchitecture
import Foundation
import Testing

@testable import VortexPlatform

/// Readings take turns, `readingsAtOnce` at a time: a reading given up ends at once and frees its turn, and one the user
/// waits for takes the next free turn before any waiting in the background. Each test has a queue of its own, so other
/// tests' readings never take its turns. Told by what happens in which order, never by the clock: a run of every suite
/// at once keeps the threads busy for tens of seconds. How soon is `ReadingPerformanceTests`' to say.
struct ReadingQueueTests {
  /// A door a reading waits at, holding its turn, until the test opens it.
  final class Door: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func wait() { semaphore.wait() }
    func open() { semaphore.signal() }
  }

  /// How long a test waits for what must come before it fails instead. In a run of every suite at once a task took 15 s
  /// to start, and Vision 25 s to end the work given up: so a good deal more. Nothing here is timed by it.
  static let patience: TimeInterval = 120

  /// Waits until `queue` holds `count` readings, running or waiting.
  func waitUntil(_ queue: ReadingQueue, holds count: Int) async throws {
    try #require(await waitFor { queue.count == count }, "the queue holds \(queue.count) readings, not \(count)")
  }

  /// Waits until `condition` holds, at most `patience`: whether it came.
  func waitFor(_ condition: () -> Bool) async -> Bool {
    let deadline = Date.now.addingTimeInterval(Self.patience)
    while !condition() {
      guard Date.now < deadline else { return false }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return true
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

  /// One given up while it reads: its caller gets `CancellationError` at once, with no text, without waiting for the work
  /// it gave up, which goes on until it next looks, as Vision's does; and its turn goes to the next reading at once, which
  /// reads while that work still goes on, a turn lent until the work ends.
  @Test
  func aReadingGivenUpWhileItReadsFreesItsTurnAtOnce() async throws {
    let queue = ReadingQueue(width: 1)
    let looking = Door()
    let events = LockIsolated<[String]>([])
    let first = Task {
      try await queue.run(.background) { read in
        // Vision's read, stopped by its cancelled requests, looks once given up: here when the test opens the door.
        while !read.wasGivenUp { usleep(1_000) }
        looking.wait()
        events.withValue { $0.append("first's work ends") }
        try read.check()
        return "first"
      }
    }
    try await waitUntil(queue, holds: 1)
    let next = Task {
      try await queue.run(.background) { _ in
        events.withValue { $0.append("next reads") }
        return "next"
      }
    }
    try await waitUntil(queue, holds: 2)
    first.cancel()
    await #expect(throws: CancellationError.self) { try await first.value }
    #expect(!events.value.contains("first's work ends"))
    // The next reading has the turn while the first's work is still held at the door.
    #expect(await waitFor { events.value.contains("next reads") }, "the next reading waited for the work given up")
    #expect(queue.turns == 2)
    looking.open()
    #expect(try await next.value == "next")
    try await waitUntil(queue, holds: 0)
    #expect(events.value == ["next reads", "first's work ends"])
    // The turn lent came back as that work ended.
    #expect(queue.turns == 1)
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

  /// A read Vision makes, its task cancelled while Vision reads, ends for its caller in `CancellationError`, with no text,
  /// and Vision's own work ends too, as best it can, giving back the turn it was lent: the tester's wide picture of small
  /// text, which takes a moment to read whole, read as written, as Screen Text reads, and given up from a thread of its
  /// own once Vision has its requests out, as Esc gives it up. It must end; how soon is `ReadingPerformanceTests`' to say.
  @Test
  func aVisionReadGivenUpEndsAndSoDoesItsWork() async throws {
    let picture = try Fixture.image("dense-wide")
    let queue = ReadingQueue(width: 1)
    let reading = LockIsolated<VisionRead?>(nil)
    let read = Task {
      try await queue.run(.interactive) { read in
        reading.setValue(read)
        return try readPieces(in: picture.cgImage, reading: .asWritten, by: read).count
      }
    }
    let patience = Self.patience
    let giver = Thread {
      let deadline = Date.now.addingTimeInterval(patience)
      while reading.value?.isReading != true, Date.now < deadline { usleep(500) }
      read.cancel()
    }
    // Ahead of the busy threads of a full run, so Vision has no time to read the whole picture first.
    giver.qualityOfService = .userInteractive
    giver.start()
    await #expect(throws: CancellationError.self) { try await read.value }
    try await waitUntil(queue, holds: 0)
    #expect(queue.turns == 1)
  }
}
