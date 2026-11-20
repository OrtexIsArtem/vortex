import Foundation
import Testing

@testable import VortexPlatform

/// How soon readings answer, timed by the clock, which only a Mac with nothing else running can hold: skipped unless
/// `VORTEX_PERFORMANCE_TESTS` is set, as in `VORTEX_PERFORMANCE_TESTS=1 swift test --package-path Packages --filter
/// PerformanceTests`. A run of every suite at once keeps the threads busy for seconds, so the normal run tells the same
/// by what happens in which order (`ReadingQueueTests`).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["VORTEX_PERFORMANCE_TESTS"] != nil, "set VORTEX_PERFORMANCE_TESTS"))
struct ReadingPerformanceTests {
  /// Esc on a dense screen: a read Vision makes, its task cancelled while Vision reads, ends for its caller within half a
  /// second, in `CancellationError` with no text: the tester's wide picture of small text, which takes a moment to read
  /// whole.
  @Test
  func aVisionReadGivenUpEndsForItsCallerWithinHalfASecond() async throws {
    let picture = try Fixture.image("dense-wide")
    let read = Task { try await TextRecognitionClient.liveValue.recognizeAsWritten(picture) }
    try await Task.sleep(for: .milliseconds(100))
    let start = ContinuousClock.now
    read.cancel()
    await #expect(throws: CancellationError.self) { try await read.value }
    #expect(ContinuousClock.now - start < .milliseconds(500))
  }
}
