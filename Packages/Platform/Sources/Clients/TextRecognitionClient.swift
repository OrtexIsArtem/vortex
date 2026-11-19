import ComposableArchitecture
import Foundation
import ImageIO
import Vision

/// Text on images, recognized on this Mac by Apple Vision, offline: Ukrainian, Russian and English. And QR codes.
@DependencyClient
public struct TextRecognitionClient: Sendable {
  /// The lines of text, top to bottom, one per line; empty when there is none. Runs in the background.
  public var recognize: @Sendable (_ image: ScreenImage) async throws -> String
  /// What a QR code in the image holds, as text: a link, or anything else it spells; nil when there is none, or none
  /// that holds text. Of several, the largest. Apple Vision's barcode detection, QR codes only. Runs in the background.
  public var readQRCode: @Sendable (_ image: ScreenImage) async throws -> String?
  /// The same from an image's data (a PNG file's), for search: read without language correction, which costs twice as
  /// much and finds nothing more, from the image scaled down to at most `searchedPixels` on its longer side; an image
  /// that shows through over white, then over black (`backgrounds`), a line read in both once. Throws for data that
  /// isn't an image. Runs in the background, and stops when its task is cancelled (`SearchRead`).
  public var recognizeForSearch: @Sendable (_ imageData: Data) async throws -> String
}

extension TextRecognitionClient: DependencyKey {
  public static let liveValue = TextRecognitionClient(
    recognize: { image in
      try await inBackground { try text(in: image.cgImage, correctsLanguage: true) }
    },
    readQRCode: { image in
      try await inBackground { try qrPayload(in: image.cgImage) }
    },
    recognizeForSearch: { imageData in
      let read = SearchRead()
      return try await withTaskCancellationHandler {
        try await inBackground { try read.text(of: imageData) }
      } onCancel: {
        read.giveUp()
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

/// The languages Vision reads, the same for both entry points. Without language correction their order makes no
/// difference.
let recognitionLanguages = ["uk-UA", "ru-RU", "en-US"]

/// An image's longer side, in pixels, past which search reads it scaled down.
let searchedPixels = 4_096

struct NotAnImage: Error {}

/// Runs a reading on the utility queue, off the caller's thread.
private func inBackground<Result: Sendable>(_ reading: @escaping @Sendable () throws -> Result) async throws -> Result {
  try await withCheckedThrowingContinuation { continuation in
    DispatchQueue.global(qos: .utility).async {
      continuation.resume(with: Swift.Result(catching: reading))
    }
  }
}

/// Vision's accurate reading of an image: its lines in `readingOrder`, joined by "\n"; empty when there is no text.
private func text(in image: CGImage, correctsLanguage: Bool) throws -> String {
  let request = textRequest(correctsLanguage: correctsLanguage)
  try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
  return lines(readBy: request)
}

/// What the largest QR code in the image holds as text; nil without one. A code that holds only bytes has no text.
private func qrPayload(in image: CGImage) throws -> String? {
  let request = VNDetectBarcodesRequest()
  request.symbologies = [.qr]
  try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
  let codes = (request.results ?? []).compactMap { code -> (payload: String, area: CGFloat)? in
    guard let payload = code.payloadStringValue, !payload.isEmpty else { return nil }
    return (payload, code.boundingBox.width * code.boundingBox.height)
  }
  return codes.max { $0.area < $1.area }?.payload
}

/// Vision's accurate reading, in `recognitionLanguages`.
private func textRequest(correctsLanguage: Bool) -> VNRecognizeTextRequest {
  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.recognitionLanguages = recognitionLanguages
  request.usesLanguageCorrection = correctsLanguage
  return request
}

/// What a request read: its lines in `readingOrder`, joined by "\n"; empty when there is no text.
private func lines(readBy request: VNRecognizeTextRequest) -> String {
  readingOrder(request.results ?? []).joined(separator: "\n")
}

/// One read for search, which its caller may give up, as Clipboard does when it stops: given up before Vision starts,
/// the image is neither decoded nor read; given up while Vision reads, Vision stops; given up the moment before Vision
/// starts, which then reads to the end, what it read is dropped. Either way the read ends in `CancellationError`.
/// Vision itself reads one request at a time, so a read given up and not stopped would hold up the next one and keep
/// its image in memory until it ended.
private final class SearchRead: @unchecked Sendable {
  private let lock = NSLock()
  private var isGivenUp = false
  private var request: VNRecognizeTextRequest?

  func giveUp() {
    lock.withLock {
      isGivenUp = true
      request?.cancel()
    }
  }

  /// The image read over each of its `backgrounds`, one after the other: the lines of the first read, then those of
  /// the next one that the first didn't read, so a line read over both, as one on an opaque part is, comes once.
  func text(of imageData: Data) throws -> String {
    try checkGivenUp()
    let image = try searchedImage(imageData)
    var lines: [String] = []
    for background in backgrounds(for: image) {
      try checkGivenUp()
      let known = Set(lines)
      lines += try read(drawn(image, over: background)).filter { !known.contains($0) }
    }
    return lines.joined(separator: "\n")
  }

  /// Vision's lines of one image, in `readingOrder`.
  private func read(_ image: CGImage) throws -> [String] {
    let request = textRequest(correctsLanguage: false)
    try lock.withLock {
      if isGivenUp { throw CancellationError() }
      self.request = request
    }
    do {
      try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    } catch {
      // A request cancelled throws Vision's own error.
      throw lock.withLock { isGivenUp } ? CancellationError() : error
    }
    // Vision ignores a cancel that comes before it starts.
    try checkGivenUp()
    return readingOrder(request.results ?? [])
  }

  private func checkGivenUp() throws {
    if lock.withLock({ isGivenUp }) { throw CancellationError() }
  }
}

/// An image's data decoded for search: a longer side over `searchedPixels` scaled down to it, a smaller image as it is,
/// and turned as its orientation says.
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

/// What search reads an image over, one after the other; nil: the image as it is. Vision takes a transparent pixel for
/// black, so text with nothing behind it (a diagram, a logo, a text layer copied from a design app) would be read only
/// when it is light. An image that shows through is read over white, then over black: text of either shade gets the
/// most contrast in one of them, which small text needs (over mid-gray, 9–11 px text is lost), whatever sits beside it.
/// One background for the whole image, picked by its shade, would hide text of the other shade, such as a logo's light
/// name beside its larger dark mark. An opaque image is read once, as it is.
func backgrounds(for image: CGImage) -> [CGColor?] {
  showsThrough(image) ? [CGColor.white, CGColor.black] : [nil]
}

/// The image drawn over `background`, so that nothing shows through it; the image itself for nil.
func drawn(_ image: CGImage, over background: CGColor?) -> CGImage {
  guard let background,
        let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
          data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
  else { return image }
  let whole = CGRect(x: 0, y: 0, width: image.width, height: image.height)
  context.setFillColor(background)
  context.fill(whole)
  context.draw(image, in: whole)
  return context.makeImage() ?? image
}

/// The side of the square, in pixels, an image is drawn into to see whether any of it shows through.
let probeSide = 256

/// Whether any of an image shows through, seen on the image drawn into a `probeSide` px square, in a few milliseconds.
/// An image with an alpha channel and nothing transparent, as many PNGs are, doesn't.
private func showsThrough(_ image: CGImage) -> Bool {
  switch image.alphaInfo {
  case .none, .noneSkipFirst, .noneSkipLast: return false
  default: break
  }
  guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
          data: nil, width: probeSide, height: probeSide, bitsPerComponent: 8, bytesPerRow: probeSide * 4, space: space,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        context.data != nil
  else { return false }
  context.interpolationQuality = .high
  context.draw(image, in: CGRect(x: 0, y: 0, width: probeSide, height: probeSide))
  let pixels = UnsafeRawBufferPointer(start: context.data, count: probeSide * probeSide * 4)
  return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 255 }
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
