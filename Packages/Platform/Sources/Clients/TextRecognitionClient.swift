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
            continuation.resume(returning: readingOrder(request.results ?? []).joined(separator: "\n"))
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

/// Lines top to bottom; pieces of text side by side on one row (columns, a sender and a time) left to right. Vision
/// measures from the bottom left, so a higher line has a larger y.
func readingOrder(_ observations: [VNRecognizedTextObservation]) -> [String] {
  readingOrder(observations, box: \.boundingBox).compactMap { $0.topCandidates(1).first?.string }
}

/// The same order for anything with a box in Vision's coordinates.
func readingOrder<Item>(_ items: [Item], box: (Item) -> CGRect) -> [Item] {
  var rows: [(midY: CGFloat, items: [Item])] = []
  for item in items.sorted(by: { box($0).midY > box($1).midY }) {
    // Within half a line's height of the row's first piece, it belongs to that row.
    if let last = rows.indices.last, abs(rows[last].midY - box(item).midY) < box(item).height / 2 {
      rows[last].items.append(item)
    } else {
      rows.append((box(item).midY, [item]))
    }
  }
  return rows.flatMap { row in row.items.sorted { box($0).minX < box($1).minX } }
}
