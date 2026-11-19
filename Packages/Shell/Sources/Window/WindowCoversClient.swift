import Combine
import ComposableArchitecture
import VortexCore

/// The covers utilities put up over the window and take down (`@Shared(.windowCover)`), as the shell hears of them.
/// Internal to the shell: only it draws a cover and keeps the window for it.
struct WindowCoversClient: Sendable {
  /// Every change of the cover after the call, the cover then or nil; not the one at the time of the call, which the
  /// shell reads as it is.
  var changes: @Sendable () async -> AsyncStream<WindowCover?>
}

extension WindowCoversClient: DependencyKey {
  static let liveValue = WindowCoversClient(
    changes: {
      @SharedReader(.windowCover) var cover
      let (stream, continuation) = AsyncStream.makeStream(of: WindowCover?.self)
      let subscription = Subscription()
      subscription.cancellable = $cover.publisher.dropFirst().sink { continuation.yield($0) }
      continuation.onTermination = { _ in subscription.cancel() }
      return stream
    }
  )

  /// None in tests, which send `windowCoverChanged` themselves.
  static let testValue = WindowCoversClient(changes: { .finished })

  /// Keeps the publisher's subscription while the stream lasts; it is set once, before anyone can cancel it.
  private final class Subscription: @unchecked Sendable {
    var cancellable: AnyCancellable?

    func cancel() {
      cancellable?.cancel()
    }
  }
}

extension DependencyValues {
  var windowCovers: WindowCoversClient {
    get { self[WindowCoversClient.self] }
    set { self[WindowCoversClient.self] = newValue }
  }
}
