import ComposableArchitecture
import CoreText
import Foundation
import ImageIO
import Vision

/// Text on images, recognized on this Mac by Apple Vision, offline: Ukrainian, Russian and English. And QR codes.
@DependencyClient
public struct TextRecognitionClient: Sendable {
  /// The lines of text, top to bottom, one per line; empty when there is none. Runs in the background, waiting its turn
  /// behind a reading the user waits for (`ReadingQueue`), and stops when its task is cancelled.
  public var recognize: @Sendable (_ image: ScreenImage) async throws -> String
  /// The same, read as written: without Vision's language correction, which puts a space after the colon in
  /// `Main.swift:42`, so code, paths and times come as they show; with the spaces between words that a second read,
  /// with correction, finds between two lowercase letters (`spaced`), as Vision alone drops some in small text, and
  /// never one inside a camelCase word. Both reads take about 3.5 times as long as one. Runs in the background, as a
  /// reading the user waits for, which takes the next free turn before the ones in the background (`ReadingQueue`), and
  /// stops when its task is cancelled.
  public var recognizeAsWritten: @Sendable (_ image: ScreenImage) async throws -> String
  /// What a QR code in the image holds, as text: a link, or anything else it spells; nil when there is none, or none
  /// that holds text. Of several, the largest. Apple Vision's barcode detection, QR codes only. Runs in the background,
  /// as a reading the user waits for, and stops when its task is cancelled.
  public var readQRCode: @Sendable (_ image: ScreenImage) async throws -> String?
  /// The same from an image's data (a PNG file's), for search: read without language correction, which costs twice as
  /// much and finds nothing more, from the image scaled down to at most `searchedPixels` on its longer side; an image
  /// that shows through over white, then over black (`backgrounds`), a line read in both once. Throws for data that
  /// isn't an image. Runs in the background, waiting its turn behind a reading the user waits for, and stops when its
  /// task is cancelled (`VisionRead`).
  public var recognizeForSearch: @Sendable (_ imageData: Data) async throws -> String
  /// Loads what a frame's read needs, so the first read after a launch doesn't wait for Vision to load it: a tiny read
  /// of two words with the same requests (a QR code, then text as written and corrected), whose result is dropped.
  /// Called as a capture begins, while the user frames; nothing keeps Vision warm otherwise. Runs in the background, as a
  /// reading the user waits for.
  public var warmUp: @Sendable () async -> Void
}

extension TextRecognitionClient: DependencyKey {
  public static let liveValue = TextRecognitionClient(
    recognize: { image in
      try await readings.run(.background) { read in try text(in: image.cgImage, reading: .corrected, by: read) }
    },
    recognizeAsWritten: { image in
      try await readings.run(.interactive) { read in try text(in: image.cgImage, reading: .asWritten, by: read) }
    },
    readQRCode: { image in
      try await readings.run(.interactive) { read in try qrPayload(in: image.cgImage, by: read) }
    },
    recognizeForSearch: { imageData in
      try await readings.run(.background) { read in try searchText(of: imageData, by: read) }
    },
    warmUp: {
      _ = try? await readings.run(.interactive) { read in try warmUpRead(by: read) }
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

// MARK: - Taking turns

/// How many readings run at once (`readings`). Vision holds a thread for each reading while it waits for work of its own
/// on other threads: 32 at once, as tests running side by side make, left no thread for that work, and none ended.
let readingsAtOnce = 2

/// Where this Mac's readings take their turns.
let readings = ReadingQueue(width: readingsAtOnce)

/// How soon a reading should run: one the user waits for, as Screen Text's, or one in the background, as Tasks' and
/// Clipboard's.
enum Urgency: Sendable {
  case interactive
  case background
}

/// Where readings take turns: `width` at a time, off the caller's thread. One the user waits for takes the next free turn
/// before any waiting in the background, and runs at a higher quality of service. A reading waiting for its turn holds
/// no thread; one whose task is cancelled ends at once with `CancellationError` and frees its turn (`VisionRead`): given
/// up while its work runs, it lends the turn to the next reading until that work, which stops when it next looks, ends.
final class ReadingQueue: Sendable {
  private let queue: OperationQueue
  private let width: Int
  /// Turns lent by readings given up while their work still runs.
  private let lent = LockIsolated(0)

  init(width: Int) {
    self.width = width
    queue = OperationQueue()
    queue.name = "Vortex text recognition"
    queue.maxConcurrentOperationCount = width
  }

  /// How many readings run or wait, a reading given up counted until its work ends.
  var count: Int { queue.operationCount }

  /// How many readings may run at once now: `width`, and one more for each reading given up whose work still runs.
  var turns: Int { queue.maxConcurrentOperationCount }

  /// `work` in its turn, with the `VisionRead` that its task's cancellation gives up.
  func run<Result: Sendable>(
    _ urgency: Urgency, _ work: @escaping @Sendable (VisionRead) throws -> Result
  ) async throws -> Result {
    let read = VisionRead()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let ending = Ending(continuation)
        let operation = BlockOperation { [self] in
          read.beginWork()
          ending.resume(with: Swift.Result {
            try read.check()
            return try work(read)
          })
          read.endWork { lend(-1) }
        }
        operation.queuePriority = urgency == .interactive ? .veryHigh : .normal
        operation.qualityOfService = urgency == .interactive ? .userInitiated : .utility
        // Given up: the work, if it runs, stops when it next looks, its turn going to the next reading meanwhile, and the
        // task goes on at once. The operation holds the reading, so the reading holds it weakly, and neither outlives its
        // turn with the picture it reads.
        read.whenGivenUp { [weak operation, weak self] in
          operation?.cancel()
          read.lendTurn { self?.lend(1) }
          ending.resume(with: .failure(CancellationError()))
        }
        queue.addOperation(operation)
      }
    } onCancel: {
      read.giveUp()
    }
  }

  /// Lends a turn, or takes one back.
  private func lend(_ change: Int) {
    lent.withValue { lent in
      lent += change
      queue.maxConcurrentOperationCount = width + lent
    }
  }
}

/// A continuation resumed once, by whichever comes first: the reading's end, or its giving up.
private final class Ending<Result: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Result, Error>?

  init(_ continuation: CheckedContinuation<Result, Error>) {
    self.continuation = continuation
  }

  func resume(with result: Swift.Result<Result, Error>) {
    let continuation = lock.withLock {
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume(with: result)
  }
}

/// One reading's requests to Vision, which its task's cancellation gives up (`giveUp`): before Vision starts, nothing
/// is read; while Vision reads, its requests are cancelled, so it stops within a moment, and the reading stops before
/// its next picture (`check`); the moment before Vision starts, which then reads to the end, what it read is dropped.
/// Either way the reading ends in `CancellationError`.
final class VisionRead: @unchecked Sendable {
  private let lock = NSLock()
  private var isGivenUp = false
  private var requests: [VNRequest] = []
  private var onGiveUp: [@Sendable () -> Void] = []
  /// Whether its work runs in its turn, and whether the turn was lent to the next reading, the reading given up meanwhile.
  private var isWorking = false
  private var hasLentTurn = false

  /// Its work begins, in its turn (`ReadingQueue`).
  func beginWork() {
    lock.withLock { isWorking = true }
  }

  /// Its work ended: a turn lent meanwhile comes back (`takeBack`).
  func endWork(takeBack: () -> Void) {
    lock.withLock {
      if hasLentTurn { takeBack() }
      isWorking = false
      hasLentTurn = false
    }
  }

  /// Given up while its work runs: its turn goes to the next reading (`lend`) until the work ends. Under the reading's
  /// lock, as `endWork`, so a turn comes back only after it was lent.
  func lendTurn(_ lend: () -> Void) {
    lock.withLock {
      guard isWorking, !hasLentTurn else { return }
      hasLentTurn = true
      lend()
    }
  }

  /// Whether the reading was given up.
  var wasGivenUp: Bool { lock.withLock { isGivenUp } }

  /// Whether Vision reads for it now: its requests are out (`perform`).
  var isReading: Bool { lock.withLock { !requests.isEmpty } }

  func giveUp() {
    let actions = lock.withLock { () -> [@Sendable () -> Void] in
      guard !isGivenUp else { return [] }
      isGivenUp = true
      requests.forEach { $0.cancel() }
      defer { onGiveUp = [] }
      return onGiveUp
    }
    actions.forEach { $0() }
  }

  /// Runs `action` once the reading is given up, at once if it already was.
  func whenGivenUp(_ action: @escaping @Sendable () -> Void) {
    let isGivenUp = lock.withLock {
      if !self.isGivenUp { onGiveUp.append(action) }
      return self.isGivenUp
    }
    if isGivenUp { action() }
  }

  /// Throws `CancellationError` once the reading is given up: looked at before each picture.
  func check() throws {
    if wasGivenUp { throw CancellationError() }
  }

  /// Vision's `requests` on `image`, unless the reading is given up.
  func perform(_ requests: [VNRequest], on image: CGImage) throws {
    try lock.withLock {
      if isGivenUp { throw CancellationError() }
      self.requests = requests
    }
    defer { lock.withLock { self.requests = [] } }
    do {
      try VNImageRequestHandler(cgImage: image, options: [:]).perform(requests)
    } catch {
      // A request cancelled throws Vision's own error.
      throw wasGivenUp ? CancellationError() : error
    }
    // Vision ignores a cancel that comes before it starts.
    try check()
  }
}

// MARK: - Reading

/// Vision's accurate reading of an image, in tiles it keeps at full resolution (`readPieces`): its lines (`lines(of:)`),
/// joined by "\n"; empty when there is no text.
private func text(in image: CGImage, reading: TextReading, by read: VisionRead) throws -> String {
  lines(of: try readPieces(in: image, reading: reading, by: read)).joined(separator: "\n")
}

/// How text is read: with Vision's language correction, or as written, with the spaces between words a corrected read
/// finds (`spaced`), which takes both reads, about three and a half times as long.
enum TextReading {
  case corrected
  case asWritten
}

/// What the largest QR code in the image holds as text; nil without one. A code that holds only bytes has no text.
private func qrPayload(in image: CGImage, by read: VisionRead) throws -> String? {
  let request = qrRequest()
  try read.perform([request], on: image)
  let codes = (request.results ?? []).compactMap { code -> (payload: String, area: CGFloat)? in
    guard let payload = code.payloadStringValue, !payload.isEmpty else { return nil }
    return (payload, code.boundingBox.width * code.boundingBox.height)
  }
  return codes.max { $0.area < $1.area }?.payload
}

/// Vision's barcode detection, QR codes only.
private func qrRequest() -> VNDetectBarcodesRequest {
  let request = VNDetectBarcodesRequest()
  request.symbologies = [.qr]
  return request
}

/// The warm-up: the requests a frame's read makes, on `warmUpPicture`, the result dropped.
private func warmUpRead(by read: VisionRead) throws {
  guard let picture = warmUpPicture() else { return }
  try read.perform([qrRequest(), textRequest(correctsLanguage: false), textRequest(correctsLanguage: true)], on: picture)
}

/// A word in Latin and one in Cyrillic letters, black on white, 240 × 56 px: text for the warm-up to read, so Vision
/// loads what reads it and not only what finds it.
func warmUpPicture() -> CGImage? {
  let width = 240, height = 56
  guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
          data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let font = CTFontCreateUIFontForLanguage(.system, 26, nil)
  else { return nil }
  context.setFillColor(CGColor(gray: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  let attributes: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
  ]
  context.textPosition = CGPoint(x: 12, y: 18)
  CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "Vortex Текст", attributes: attributes)), context)
  return context.makeImage()
}

/// Vision's accurate reading, in `recognitionLanguages`.
private func textRequest(correctsLanguage: Bool) -> VNRecognizeTextRequest {
  let request = VNRecognizeTextRequest()
  request.recognitionLevel = .accurate
  request.recognitionLanguages = recognitionLanguages
  request.usesLanguageCorrection = correctsLanguage
  return request
}

/// The text of an image's data, for search (`recognizeForSearch`): the image read over each of its `backgrounds`, one
/// after the other, the lines of the first read, then those of the next one that the first didn't read, so a line read
/// over both, as one on an opaque part is, comes once. Given up before Vision starts, the image is neither decoded nor
/// read (`VisionRead`).
private func searchText(of imageData: Data, by read: VisionRead) throws -> String {
  try read.check()
  let image = try searchedImage(imageData)
  var lines: [String] = []
  for background in backgrounds(for: image) {
    let known = Set(lines)
    let request = textRequest(correctsLanguage: false)
    try read.perform([request], on: drawn(image, over: background))
    lines += readingLines(request.results ?? []).filter { !known.contains($0) }
  }
  return lines.joined(separator: "\n")
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

// MARK: - Reading in tiles

/// The side of the tiles a picture is read in, in pixels. Vision shrinks a larger picture before it reads it, and small
/// text drops below what it can read: with 11 pt text at 2x, a picture 2,000 px wide is read whole, one 2,100–2,300 px
/// wide in part and one 2,400 px wide not at all; one 2,234 px tall whole and one 2,400 px tall in part. 1,600 px each
/// way leaves a safe margin. A whole screen of 3,456 × 2,234 px is six tiles.
let tileSide = 1_600
/// How much neighbouring tiles overlap at least, in pixels: a line two tiles cut is long enough in both to be stitched,
/// and one two rows of tiles cut is whole in one of them.
let tileOverlap = 240

/// Where a picture `width` × `height` px is cut into tiles of at most `side` px each way, spread evenly so that
/// neighbours overlap by at least `overlap` px; one tile when the picture is small enough. In pixels from the top left.
func tiles(width: Int, height: Int, side: Int = tileSide, overlap: Int = tileOverlap) -> [CGRect] {
  func spans(_ length: Int) -> [(start: Int, length: Int)] {
    guard length > side else { return [(0, length)] }
    let count = Int((Double(length - overlap) / Double(side - overlap)).rounded(.up))
    let stride = Double(length - side) / Double(count - 1)
    return (0..<count).map { (Int((Double($0) * stride).rounded()), side) }
  }
  return spans(height).flatMap { row in
    spans(width).map { column in CGRect(x: column.start, y: row.start, width: column.length, height: row.length) }
  }
}

/// Whether a piece read in `tile`, from `top` to `bottom` in the picture's pixels from its top, is whole: not cut by an
/// edge the tile shares with the tile above or below, which holds the piece whole. The picture's own edges cut nothing.
func isWhole(top: CGFloat, bottom: CGFloat, in tile: CGRect, pictureHeight: CGFloat) -> Bool {
  let slack: CGFloat = 2
  let cutAtTop = tile.minY > 0 && top <= tile.minY + slack
  let cutAtBottom = tile.maxY < pictureHeight && bottom >= tile.maxY - slack
  return !cutAtTop && !cutAtBottom
}

/// A piece of text Vision read in one tile, with its box in the whole picture, in Vision's coordinates (0…1, from the
/// bottom left).
struct ReadPiece: Equatable {
  var text: String
  var box: CGRect
  var tile: Int
}

/// The picture's pieces of text, read tile by tile at full resolution (`tiles`), each piece once whole: one a tile's
/// inner top or bottom edge cuts is left out (`isWhole`).
func readPieces(in image: CGImage, reading: TextReading, by read: VisionRead) throws -> [ReadPiece] {
  let width = CGFloat(image.width), height = CGFloat(image.height)
  var pieces: [ReadPiece] = []
  for (index, tile) in tiles(width: image.width, height: image.height).enumerated() {
    let isWholePicture = tile.size == CGSize(width: width, height: height)
    guard let part = isWholePicture ? image : image.cropping(to: tile) else { continue }
    for (text, box) in try texts(in: part, reading: reading, by: read) {
      let top = tile.minY + (1 - box.maxY) * tile.height
      let bottom = tile.minY + (1 - box.minY) * tile.height
      guard isWhole(top: top, bottom: bottom, in: tile, pictureHeight: height) else { continue }
      let inPicture = CGRect(
        x: (tile.minX + box.minX * tile.width) / width,
        y: 1 - bottom / height,
        width: box.width * tile.width / width,
        height: (bottom - top) / height
      )
      pieces.append(ReadPiece(text: text, box: inPicture, tile: index))
    }
  }
  return pieces
}

/// The pieces of text Vision reads in one picture, with their boxes in Vision's coordinates. As written, a piece takes
/// the spaces between letters from the corrected read of the same place (`spaced`): the corrected piece that covers
/// most of it, where the two share more than half of the larger one.
private func texts(in image: CGImage, reading: TextReading, by read: VisionRead) throws -> [(text: String, box: CGRect)] {
  func pieces(_ request: VNRecognizeTextRequest) -> [(text: String, box: CGRect)] {
    (request.results ?? []).compactMap { observation in
      guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
      return (text, observation.boundingBox)
    }
  }
  let corrected = textRequest(correctsLanguage: true)
  guard reading == .asWritten else {
    try read.perform([corrected], on: image)
    return pieces(corrected)
  }
  let written = textRequest(correctsLanguage: false)
  try read.perform([written, corrected], on: image)
  let correctedPieces = pieces(corrected)
  /// The share of the larger box that the two boxes have in common.
  func shared(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let common = a.intersection(b)
    guard !common.isNull else { return 0 }
    return common.width * common.height / max(a.width * a.height, b.width * b.height, .leastNonzeroMagnitude)
  }
  return pieces(written).map { piece in
    guard let match = correctedPieces.max(by: { shared($0.box, piece.box) < shared($1.box, piece.box) }),
          shared(match.box, piece.box) > 0.5
    else { return piece }
    return (spaced(piece.text, as: match.text), piece.box)
  }
}

/// The lines the pieces make (`readingRows`), the pieces of a row joined by a space, left to right; a stretch two tiles
/// both read comes once, and a line a tile's edge cuts is stitched (`merged`).
func lines(of pieces: [ReadPiece]) -> [String] {
  readingRows(pieces, box: \.box).compactMap { row in
    var merged: [ReadPiece] = []
    for piece in row {
      if let last = merged.last, last.tile != piece.tile, piece.box.minX < last.box.maxX {
        merged[merged.count - 1] = VortexPlatform.merged(last, piece)
      } else {
        merged.append(piece)
      }
    }
    let line = merged.map(\.text).joined(separator: " ")
    return line.isEmpty ? nil : line
  }
}

/// Two reads from neighbouring tiles whose stretches overlap on a row, `a` starting first, as one: of two reads of the
/// same stretch, the one that parts more words (`wordGaps`), as Vision's slip in small text is to run two together, `a`
/// when neither does; else the one that holds the other's stretch, or the two stitched where they agree (`stitched`).
func merged(_ a: ReadPiece, _ b: ReadPiece) -> ReadPiece {
  // About 7 px of a whole screen's width: reads of one stretch end a few pixels apart.
  let slack: CGFloat = 0.002
  if abs(a.box.minX - b.box.minX) <= slack, abs(a.box.maxX - b.box.maxX) <= slack, wordGaps(b.text) > wordGaps(a.text) {
    return ReadPiece(text: b.text, box: a.box.union(b.box), tile: b.tile)
  }
  if b.box.maxX <= a.box.maxX + slack { return ReadPiece(text: a.text, box: a.box.union(b.box), tile: a.tile) }
  if a.box.minX >= b.box.minX - slack { return ReadPiece(text: b.text, box: a.box.union(b.box), tile: b.tile) }
  return ReadPiece(text: stitched(a, b), box: a.box.union(b.box), tile: b.tile)
}

/// How many spaces a text has between two lowercase letters (`isLowercaseLetter`): the gaps between words that Vision
/// may miss in small text.
func wordGaps(_ text: String) -> Int {
  let characters = Array(text)
  return characters.indices.dropFirst().dropLast().filter { index in
    characters[index] == " " && characters[index - 1].isLowercaseLetter && characters[index + 1].isLowercaseLetter
  }.count
}

extension Character {
  /// A lowercase letter, in any script: the only letters a space from a corrected read may come between, as one where a
  /// lowercase letter meets a capital, or between two capitals, parts a word of code (`query Selector`, `URL Session`).
  var isLowercaseLetter: Bool { isLetter && isLowercase }
}

/// A line two tiles cut, `a` the left part and `b` the right, each read up to its tile's edge, where letters may be cut
/// and misread: the longest run of at least 3 characters the two agree on in their overlap joins them, a's characters
/// after it and b's before it left out. Without one, each keeps its part up to the overlap's middle.
func stitched(_ a: ReadPiece, _ b: ReadPiece) -> String {
  let left = Array(a.text), right = Array(b.text)
  let overlapStart = b.box.minX, overlapEnd = min(a.box.maxX, b.box.maxX)
  /// How many of a piece's characters lie between `start` and `end`, by their share of its width.
  func characters(of characters: [Character], in box: CGRect, from start: CGFloat, to end: CGFloat) -> Int {
    guard box.width > 0 else { return 0 }
    let share = min(max((end - start) / box.width, 0), 1)
    return Int((share * CGFloat(characters.count)).rounded())
  }
  // The characters in the overlap, and a few to spare.
  let tail = Array(left.suffix(characters(of: left, in: a.box, from: overlapStart, to: overlapEnd) + 3))
  let head = Array(right.prefix(characters(of: right, in: b.box, from: overlapStart, to: overlapEnd) + 3))
  // The longest common run of the tail and the head: its length, and where it ends in each.
  var best = (length: 0, tailEnd: 0, headEnd: 0)
  var previous = [Int](repeating: 0, count: head.count + 1)
  for i in tail.indices {
    var current = [Int](repeating: 0, count: head.count + 1)
    for j in head.indices where tail[i] == head[j] {
      current[j + 1] = previous[j] + 1
      if current[j + 1] > best.length { best = (current[j + 1], i + 1, j + 1) }
    }
    previous = current
  }
  if best.length >= 3 {
    let leftEnd = left.count - tail.count + best.tailEnd - best.length
    let rightStart = best.headEnd - best.length
    return String(left[..<leftEnd]) + String(right[rightStart...])
  }
  let middle = (overlapStart + overlapEnd) / 2
  let leftKeep = characters(of: left, in: a.box, from: a.box.minX, to: middle)
  let rightDrop = characters(of: right, in: b.box, from: b.box.minX, to: middle)
  return String(left.prefix(leftKeep)) + String(right.dropFirst(rightDrop))
}

// MARK: - Reading as written

/// A piece read as written, `written`, with a space wherever the corrected read of it, `corrected`, has one between two
/// lowercase letters and `written` doesn't: read as written, Vision drops a space between words in small text
/// ("overthe"), and read with correction, it adds one after a colon in code ("Main.swift: 42") and parts camelCase
/// ("query Selector"), so a space where a lowercase letter meets a capital, or between two capitals, never comes. Every
/// character of `written` stays, its spaces too; a space comes only between two of its characters that match two
/// neighbours of `corrected`, so a letter either read got wrong elsewhere ("14-he" for "14 - The") doesn't keep the rest
/// of the piece from its spaces.
func spaced(_ written: String, as corrected: String) -> String {
  let writtenCharacters = written.filter { $0 != " " }.map(\.self)
  // The corrected read's characters other than spaces, each with whether a space between two lowercase letters comes
  // before it.
  var correctedCharacters: [Character] = [], spaceBefore: [Bool] = [], afterSpace = false
  for character in corrected {
    if character == " " {
      afterSpace = true
      continue
    }
    spaceBefore.append(afterSpace && correctedCharacters.last?.isLowercaseLetter == true && character.isLowercaseLetter)
    correctedCharacters.append(character)
    afterSpace = false
  }
  // The longest run the two have in common, character by character, in order: `common[i][j]` for the characters from
  // `i` and from `j` on.
  let count = writtenCharacters.count, correctedCount = correctedCharacters.count
  var common = [[Int]](repeating: [Int](repeating: 0, count: correctedCount + 1), count: count + 1)
  for i in stride(from: count - 1, through: 0, by: -1) {
    for j in stride(from: correctedCount - 1, through: 0, by: -1) {
      common[i][j] = writtenCharacters[i] == correctedCharacters[j]
        ? common[i + 1][j + 1] + 1 : max(common[i + 1][j], common[i][j + 1])
    }
  }
  var matches: [(written: Int, corrected: Int)] = []
  var i = 0, j = 0
  while i < count, j < correctedCount {
    if writtenCharacters[i] == correctedCharacters[j] {
      matches.append((i, j))
      i += 1
      j += 1
    } else if common[i + 1][j] >= common[i][j + 1] {
      i += 1
    } else {
      j += 1
    }
  }
  var spaceBeforeWritten: Set<Int> = []
  for (previous, next) in zip(matches, matches.dropFirst())
  where next.written == previous.written + 1 && next.corrected == previous.corrected + 1 && spaceBefore[next.corrected] {
    spaceBeforeWritten.insert(next.written)
  }
  guard !spaceBeforeWritten.isEmpty else { return written }
  var result = "", index = 0
  for character in written {
    if character != " " {
      if spaceBeforeWritten.contains(index), result.last != " " { result.append(" ") }
      index += 1
    }
    result.append(character)
  }
  return result
}

/// The lines Vision read, top to bottom: the pieces of a row (a message and its time, a line number and its line, a
/// line Vision read in parts) joined by a space, left to right (`readingRows`). Vision measures from the bottom left, so
/// a higher line has a larger y.
func readingLines(_ observations: [VNRecognizedTextObservation]) -> [String] {
  readingLines(observations, box: \.boundingBox) { $0.topCandidates(1).first?.string ?? "" }
}

/// The same lines for anything with a box in Vision's coordinates and a text.
func readingLines<Item>(_ items: [Item], box: (Item) -> CGRect, text: (Item) -> String) -> [String] {
  readingRows(items, box: box)
    .map { row in row.map(text).filter { !$0.isEmpty }.joined(separator: " ") }
    .filter { !$0.isEmpty }
}

/// The pieces in reading order, row after row (`readingRows`).
func readingOrder<Item>(_ items: [Item], box: (Item) -> CGRect) -> [Item] {
  readingRows(items, box: box).flatMap(\.self)
}

/// Pieces of text grouped into rows by where they are: rows top to bottom, a row's pieces left to right. A piece shares
/// a row with its first piece when the two overlap from top to bottom by at least half the lower one's height, so a
/// smaller time set on a message's baseline, or a slightly slanted line, stays on its row, and the next line doesn't.
func readingRows<Item>(_ items: [Item], box: (Item) -> CGRect) -> [[Item]] {
  var rows: [(first: CGRect, items: [Item])] = []
  for item in items.sorted(by: { box($0).midY > box($1).midY }) {
    let piece = box(item)
    if let row = rows.indices.last(where: { sharesRow(rows[$0].first, piece) }) {
      rows[row].items.append(item)
    } else {
      rows.append((piece, [item]))
    }
  }
  return rows.map { row in row.items.sorted { box($0).minX < box($1).minX } }
}

/// Whether two boxes overlap from top to bottom by at least half the lower one's height.
func sharesRow(_ a: CGRect, _ b: CGRect) -> Bool {
  min(a.maxY, b.maxY) - max(a.minY, b.minY) >= min(a.height, b.height) / 2
}
