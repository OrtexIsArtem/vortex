import AppKit
import Testing

@testable import VortexPlatform

/// Reads and writes a private pasteboard, never the one the user copies to. One pasteboard for all tests,
/// so runs do not pile up pasteboards in the system; hence one test at a time.
@MainActor
@Suite(.serialized)
struct PasteboardFormatTests {
  let pasteboard = NSPasteboard(name: NSPasteboard.Name("io.github.ortexisartem.vortex.tests"))

  var content: PasteboardContent? {
    PasteboardFormat.content(of: pasteboard, types: pasteboard.types ?? [])
  }

  static let png: Data = {
    let image = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    return image.representation(using: .png, properties: [:])!
  }()

  @Test
  func textIsKeptAsItIs() {
    pasteboard.clearContents()
    pasteboard.setString("  SELECT *\nFROM orders  ", forType: .string)
    #expect(content == .text("  SELECT *\nFROM orders  "))
  }

  @Test
  func aLoneWebAddressIsALink() {
    pasteboard.clearContents()
    pasteboard.setString(" https://github.com/OrtexIsArtem/vortex \n", forType: .string)
    #expect(content == .link(URL(string: "https://github.com/OrtexIsArtem/vortex")!))
  }

  @Test
  func textAroundAnAddressStaysText() {
    pasteboard.clearContents()
    pasteboard.setString("see https://example.com", forType: .string)
    #expect(content == .text("see https://example.com"))
  }

  @Test
  func blankTextIsSkipped() {
    pasteboard.clearContents()
    pasteboard.setString(" \n ", forType: .string)
    #expect(content == nil)
  }

  @Test
  func filesComeBeforeTheirIconAndName() {
    let file = URL(fileURLWithPath: "/tmp/Vortex-1.4.2.ipa")
    pasteboard.clearContents()
    pasteboard.writeObjects([file as NSURL])
    pasteboard.setString("Vortex-1.4.2.ipa", forType: .string)
    pasteboard.setData(Self.png, forType: .png)
    #expect(content == .files([file]))
  }

  @Test
  func anImageCopiedWithItsAddressIsAnImage() {
    pasteboard.clearContents()
    pasteboard.setData(Self.png, forType: .png)
    pasteboard.setString("https://example.com/cat.png", forType: .string)
    #expect(content == .image(Self.png))
  }

  @Test
  func tiffImagesBecomePNG() throws {
    let tiff = try #require(NSBitmapImageRep(data: Self.png)?.tiffRepresentation)
    pasteboard.clearContents()
    pasteboard.setData(tiff, forType: .tiff)
    guard case let .image(png) = content else {
      Issue.record("Expected an image")
      return
    }
    #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
  }

  @Test
  func transientCopiesAreSkipped() {
    pasteboard.clearContents()
    pasteboard.setString("one-time code", forType: .string)
    pasteboard.setData(Data(), forType: PasteboardFormat.transientType)
    #expect(PasteboardFormat.read(pasteboard) == nil)
  }

  @Test
  func concealedCopiesAreMarked() {
    pasteboard.clearContents()
    pasteboard.setString("hunter2", forType: .string)
    pasteboard.setData(Data(), forType: PasteboardFormat.concealedType)
    #expect(PasteboardFormat.read(pasteboard)?.isConcealed == true)
  }

  @Test
  func whatVortexWritesReadsBackButIsNotRecorded() {
    for written in [
      PasteboardContent.text("hello"),
      .link(URL(string: "https://example.com/a?b=c")!),
      .files([URL(fileURLWithPath: "/tmp/a.zip"), URL(fileURLWithPath: "/tmp/b.dmg")]),
      .image(Self.png),
    ] {
      PasteboardFormat.write(written, isConcealed: true, to: pasteboard)
      #expect(content == written)
      #expect(pasteboard.types?.contains(PasteboardFormat.concealedType) == true)
      #expect(PasteboardFormat.read(pasteboard) == nil)
    }
  }

  @Test
  func theWatcherReportsNewCopiesOnly() async {
    pasteboard.clearContents()
    pasteboard.setString("before", forType: .string)
    let (copies, continuation) = AsyncStream.makeStream(of: PasteboardCopy.self)
    let watcher = PasteboardWatcher(pasteboard: pasteboard) { continuation.yield($0) }
    watcher.start()
    defer { watcher.stop() }
    try? await Task.sleep(for: .milliseconds(100))
    pasteboard.clearContents()
    pasteboard.setString("after", forType: .string)
    var iterator = copies.makeAsyncIterator()
    let copy = await iterator.next()
    #expect(copy?.content == .text("after"))
  }
}
