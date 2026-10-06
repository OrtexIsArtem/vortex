import ComposableArchitecture
import Foundation
import Vision

/// Text on images, recognized on this Mac by Apple Vision, offline: Ukrainian, Russian and English.
@DependencyClient
public struct TextRecognitionClient: Sendable {
  /// The lines of text, top to bottom, one per line; empty when there is none. Runs in the background.
  public var recognize: @Sendable (_ image: ScreenImage) async throws -> String
}

extension TextRecognitionClient: DependencyKey {
  public static let liveValue = TextRecognitionClient(
    recognize: { image in
      try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
          let request = VNRecognizeTextRequest()
          request.recognitionLevel = .accurate
          request.recognitionLanguages = ["uk-UA", "ru-RU", "en-US"]
          request.usesLanguageCorrection = true
          do {
            try VNImageRequestHandler(cgImage: image.cgImage, options: [:]).perform([request])
            // Vision measures from the bottom left: higher lines first, then left to right.
            let lines = (request.results ?? [])
              .sorted { abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.005
                ? $0.boundingBox.midY > $1.boundingBox.midY
                : $0.boundingBox.minX < $1.boundingBox.minX }
              .compactMap { $0.topCandidates(1).first?.string }
            continuation.resume(returning: lines.joined(separator: "\n"))
          } catch {
            continuation.resume(throwing: error)
          }
        }
      }
    }
  )

  public static let testValue = TextRecognitionClient()
}

extension DependencyValues {
  public var textRecognitionClient: TextRecognitionClient {
    get { self[TextRecognitionClient.self] }
    set { self[TextRecognitionClient.self] = newValue }
  }
}
