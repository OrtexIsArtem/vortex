import ComposableArchitecture
import Foundation
import ImageIO
import Vision

/// Text on images, recognized on this Mac by Apple Vision, offline: Ukrainian, Russian and English.
@DependencyClient
public struct TextRecognitionClient: Sendable {
  /// The lines of text, top to bottom, one per line; empty when there is none. Runs in the background.
  public var recognize: @Sendable (_ image: ScreenImage) async throws -> String
  /// The same from an image's data (a PNG file's), for search: read without language correction, which costs twice as
  /// much and finds nothing more, from the image scaled down to at most `searchedPixels` on its longer side. Throws
  /// for data that isn't an image. Runs in the background.
  public var recognizeForSearch: @Sendable (_ imageData: Data) async throws -> String
}

extension TextRecognitionClient: DependencyKey {
  public static let liveValue = TextRecognitionClient(
    recognize: { image in
      try await inBackground { try text(in: image.cgImage, correctsLanguage: true) }
    },
    recognizeForSearch: { imageData in
      try await inBackground { try text(in: searchedImage(imageData), correctsLanguage: false) }
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

/// The languages Vision reads, the same for both entry points. Without language correction their order makes no
/// difference.
let recognitionLanguages = ["uk-UA", "ru-RU", "en-US"]

/// An image's longer side, in pixels, past which search reads it scaled down.
let searchedPixels = 4_096

struct NotAnImage: Error {}

/// Runs a reading on the utility queue, off the caller's thread.
private func inBackground(_ reading: @escaping @Sendable () throws -> String) async throws -> String {
  try await withCheckedThrowingContinuation { continuation in
    DispatchQueue.global(qos: .utility).async {
      continuation.resume(with: Result(catching: reading))
    }
  }
}

/// Vision's accurate reading of an image: its lines in `readingOrder`, joined by "\n"; empty when there is no text.
private func text(in image: CGImage, correctsLanguage: Bool) throws -> String {
  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.recognitionLanguages = recognitionLanguages
  request.usesLanguageCorrection = correctsLanguage
  try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
  return readingOrder(request.results ?? []).joined(separator: "\n")
}

/// An image's data decoded for search: a longer side over `searchedPixels` scaled down to it, a smaller image as it is,
/// turned as its orientation says.
func searchedImage(_ data: Data) throws -> CGImage {
  let options: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: searchedPixels,
  ]
  guard let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  else { throw NotAnImage() }
  return image
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
