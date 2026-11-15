import ComposableArchitecture
import Foundation
import GRDB
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureClipboard

/// Search finds an image copied from now on by the text on it: read once in the background after it is saved, one
/// image at a time, and kept with look-alike letters folded.
extension ClipboardFeatureTests {
  /// Reads images in place of Vision: each image's file reads as its item's id, which the reader then says the text of
  /// (`texts`, "" for any other), after `delay` on the test clock, or fails for the ids in `failing`. Returns the ids
  /// it was asked to read, in order.
  func readImages(
    _ store: TestStoreOf<ClipboardFeature>,
    texts: [UUID: String],
    delay: Duration = .seconds(1),
    failing: Set<UUID> = []
  ) -> LockIsolated<[UUID]> {
    let reads = LockIsolated<[UUID]>([])
    store.dependencies.fileClient.read = { url in Data(url.deletingLastPathComponent().lastPathComponent.utf8) }
    store.dependencies.textRecognitionClient.recognizeForSearch = { [clock] data in
      struct Unreadable: Error {}
      guard let id = UUID(uuidString: String(decoding: data, as: UTF8.self)) else { throw Unreadable() }
      reads.withValue { $0.append(id) }
      try await clock.sleep(for: delay)
      if failing.contains(id) { throw Unreadable() }
      return texts[id] ?? ""
    }
    return reads
  }

  /// The item a copied image becomes once its file is written, copied just now.
  func imageItem(_ png: Data, id: Int, from source: AppInfo = Self.terminal) -> ClipboardItem {
    ClipboardItem(
      id: uuid(id), content: .image(fileName: ClipboardFeature.imageFileName(copiedAt: now.value)), source: source,
      copiedAt: now.value, fingerprint: ClipboardCopy.fingerprint(of: .image(png)), byteSize: png.count
    )
  }

  /// Copies an image and lets its insert land; its reading starts.
  func copyImage(_ png: Data, from source: AppInfo = Self.terminal, _ store: TestStoreOf<ClipboardFeature>) async {
    copy(.image(png), from: source)
    await store.receive(\.imageSaved)
    await store.receive(\.written)
  }

  /// Lets the image being read return, and its text land.
  func finishReading(_ store: TestStoreOf<ClipboardFeature>) async {
    await clock.advance(by: .seconds(1))
    await store.receive(\.imageRead)
    await store.receive(\.written)
  }

  func searchText(_ id: UUID) throws -> String? {
    try row(id)?["searchText"] as String?
  }

  @Test
  func aNewImageIsReadOnceAndFoundByItsTextAndStillByItsApp() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    let reads = readImages(store, texts: [uuid(0): "Release notes\nmcp server"])
    await start(store)
    await copyImage(Data("screenshot".utf8), from: Self.preview, store)
    await finishReading(store)
    let image = try #require(store.state.items.first?.content)

    #expect(try searchText(uuid(0)) == "preview\nrelease notes\nmcp server")
    #expect(await search("mcp", store) == [image])
    #expect(await search("SERVER release", store) == [image])
    #expect(await search("preview", store) == [image])
    #expect(await search("mcp notes preview", store) == [image])
    #expect(await search("mcp invoice", store).isEmpty)
    // Read once: nothing waits, and nothing reads it again.
    await clock.advance(by: .seconds(10))
    #expect(reads.value == [uuid(0)])
    #expect(store.state.imagesToRead.isEmpty)
    #expect(store.state.readingImage == nil)
    await store.send(.stop)
  }

  @Test
  func lookAlikeLettersNeverBlockAMatchInAnImagesText() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    // OCR's twins both ways: Cyrillic "МСР" for "MCP", and "ТОКЕН" read in Cyrillic or as the Latin "TOKEH".
    _ = readImages(store, texts: [uuid(0): "МСР SERVER ТОКЕН", uuid(1): "Новий TOKEH"])
    await start(store)
    await copyImage(Data("cyrillic".utf8), store)
    await finishReading(store)
    await copyImage(Data("latin".utf8), store)
    await finishReading(store)
    let cyrillic = try #require(store.state.items[id: uuid(0)]?.content)
    let latin = try #require(store.state.items[id: uuid(1)]?.content)
    copy(.text("токен"))
    await store.receive(\.written)
    copy(.text("take a break"))
    await store.receive(\.written)

    #expect(await search("mcp", store) == [cyrillic])
    #expect(await search("MCP server", store) == [cyrillic])
    #expect(await search("мср", store) == [cyrillic])
    #expect(await search("токен", store) == [.text("токен"), latin, cyrillic])
    #expect(await search("tokeh", store) == [latin, cyrillic])
    #expect(await search("новий токен", store) == [latin])
    // A text matches only as typed: "tokeh" doesn't find "токен" (above), nor the Ukrainian "так" the English "take".
    #expect(await search("так", store).isEmpty)
    #expect(await search("take", store) == [.text("take a break")])
    await store.send(.stop)
  }

  @Test
  func anImagesAppNameMatchesOnlyAsTypedAndOnlyTheTextReadFromItMatchesLookAlikes() async throws {
    // An image copied before this version, never read, and a text, both from Terminal.
    let old = ClipboardItem(
      id: uuid(10), content: .image(fileName: "Image.png"), source: Self.terminal,
      copiedAt: now.value.addingTimeInterval(-120), fingerprint: "image:10", byteSize: 10
    )
    try saveRows([old, item("hello", id: 11, copiedAt: now.value.addingTimeInterval(-60))])
    let store = makeStore()
    store.exhaustivity = .off
    _ = readImages(store, texts: [uuid(0): "Тест"])
    await store.send(.start)
    await store.receive(\.loaded)
    await copyImage(Data("new".utf8), store)
    await finishReading(store)
    let new = try #require(store.state.items[id: uuid(0)]?.content)

    // The Cyrillic "те" starts the text read from the new image ("tect", folded), and never matches "terminal".
    #expect(await search("те", store) == [new])
    #expect(await search("тест", store) == [new])
    #expect(await search("тerminal", store).isEmpty)
    #expect(await search("terminal", store) == [new, .text("hello"), old.content])
    await store.send(.stop)
  }

  @Test
  func anImagesTextIsKeptLowercasedWithLookAlikesFoldedAndOnlyItsFirst16KB() {
    #expect(ClipboardItem.lookAlike("мср токен") == "mcp tokeh")
    #expect(ClipboardItem.lookAlike("авекмнорстухіјѕ") == "abekmhopctyxijs")
    // Every other letter stays, Ukrainian ones included, and so does Latin.
    #expect(ClipboardItem.lookAlike("привіт, їжак ґанок; mcp") == "пpиbit, їжak ґahok; mcp")
    #expect(ClipboardItem.imageSearchBody("МСР Server\nТОКЕН") == "mcp server\ntokeh")
    #expect(ClipboardItem.imageSearchBody(String(repeating: "B", count: 20_000)) == String(repeating: "b", count: 16_384))
    // The 16 KB are of the text as read: 8,192 two-byte letters, folded to one byte each.
    #expect(ClipboardItem.imageSearchBody(String(repeating: "Т", count: 10_000)) == String(repeating: "t", count: 8_192))
    #expect(ClipboardItem.imageSearchBody("") == "")
  }

  /// Exhaustive: each image waits its turn in `imagesToRead`, and the reader is asked for the next only once the one
  /// before returns.
  @Test
  func imagesCopiedQuicklyAreReadOneAfterTheOther() async throws {
    let store = makeStore()
    let reads = readImages(store, texts: [uuid(0): "first", uuid(1): "second"])
    await start(store)
    let (pngA, pngB) = (Data("image a".utf8), Data("image b".utf8))
    copy(.image(pngA))
    await store.receive(\.copied)
    let a = imageItem(pngA, id: 0)
    await store.receive(\.imageSaved) {
      $0.items = [a]
      $0.queuedWrites = [.insert(a)]
      $0.writing = 1
      $0.readingImage = a.id
    }
    await store.receive(\.written) {
      $0.queuedWrites = []
      $0.writing = 0
    }
    copy(.image(pngB))
    await store.receive(\.copied)
    let b = imageItem(pngB, id: 1)
    await store.receive(\.imageSaved) {
      $0.items = [b, a]
      $0.queuedWrites = [.insert(b)]
      $0.writing = 1
      $0.imagesToRead = [b.id]
    }
    await store.receive(\.written) {
      $0.queuedWrites = []
      $0.writing = 0
    }
    #expect(reads.value == [a.id])

    await clock.advance(by: .seconds(1))
    await store.receive(.imageRead(a.id, body: "first")) {
      $0.imagesToRead = []
      $0.readingImage = b.id
      $0.queuedWrites = [.text(a.id, body: "first")]
      $0.writing = 1
    }
    await store.receive(\.written) {
      $0.queuedWrites = []
      $0.writing = 0
    }
    await clock.advance(by: .seconds(1))
    await store.receive(.imageRead(b.id, body: "second")) {
      $0.readingImage = nil
      $0.queuedWrites = [.text(b.id, body: "second")]
      $0.writing = 1
    }
    await store.receive(\.written) {
      $0.queuedWrites = []
      $0.writing = 0
    }
    #expect(reads.value == [a.id, b.id])
    await store.send(.stop)
    #expect(try searchText(a.id) == "terminal\nfirst")
    #expect(try searchText(b.id) == "terminal\nsecond")
  }

  @Test
  func anImageRemovedBeforeItsTurnIsNeverReadAndOneRemovedWhileReadGetsNoWrite() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    let reads = readImages(store, texts: [uuid(0): "first", uuid(1): "second", uuid(2): "third"])
    await start(store)
    for index in 0..<3 {
      await copyImage(Data("image \(index)".utf8), store)
    }
    #expect(store.state.readingImage == uuid(0))
    #expect(store.state.imagesToRead == [uuid(1), uuid(2)])

    // The second goes before its turn, the first while it is being read.
    await store.send(.deleteTapped(uuid(1)))
    await store.receive(\.written)
    await store.send(.deleteTapped(uuid(0)))
    await store.receive(\.written)
    await clock.advance(by: .seconds(1))
    await store.receive(.imageRead(uuid(0), body: "first")) {
      // Nothing is written for it, and the third is read next.
      $0.queuedWrites = []
      $0.writing = 0
      $0.readingImage = uuid(2)
      $0.imagesToRead = []
    }
    await finishReading(store)
    #expect(reads.value == [uuid(0), uuid(2)])
    #expect(try rowCount() == 1)
    #expect(try searchText(uuid(2)) == "terminal\nthird")
    await store.send(.stop)
  }

  @Test
  func anImageThatTurnsSecretIsNeverReadAndGetsNoText() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    let reads = readImages(store, texts: [uuid(0): "first", uuid(1): "second"])
    await start(store)
    let (pngA, pngB) = (Data("image a".utf8), Data("image b".utf8))
    await copyImage(pngA, store)
    await copyImage(pngB, store)

    // A password manager copies both again, marked secret: their rows go at once. The first is being read, the second
    // waits its turn.
    copy(.image(pngB), from: Self.passwords, concealed: true)
    await store.receive(\.written)
    copy(.image(pngA), from: Self.passwords, concealed: true)
    await store.receive(\.written)
    await clock.advance(by: .seconds(1))
    await store.receive(.imageRead(uuid(0), body: "first")) {
      $0.queuedWrites = []
      $0.readingImage = nil
      $0.imagesToRead = []
    }
    await clock.advance(by: .seconds(10))
    #expect(reads.value == [uuid(0)])
    #expect(store.state.items.map(\.isConcealed) == [true, true])
    #expect(try rowCount() == 0)
    await store.send(.stop)
  }

  @Test
  func anImageSetAsideByClearAndBroughtBackByUndoKeepsTheTextThatLandedMeanwhile() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    _ = readImages(store, texts: [uuid(0): "mcp server"])
    await start(store)
    await copyImage(Data("screenshot".utf8), from: Self.preview, store)
    await store.send(.clearTapped)
    #expect(store.state.items.isEmpty)

    // Read while it is set aside: its row is still there, so its text lands.
    await finishReading(store)
    #expect(try searchText(uuid(0)) == "preview\nmcp server")
    await store.send(.undoTapped)
    #expect(await search("mcp", store).count == 1)
    #expect(try searchText(uuid(0)) == "preview\nmcp server")
    await store.send(.stop)
  }

  @Test
  func anImageClearedForGoodBeforeItsTextComesGetsNoWrite() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    _ = readImages(store, texts: [uuid(0): "mcp server"], delay: .seconds(10))
    await start(store)
    await copyImage(Data("screenshot".utf8), store)
    await store.send(.clearTapped)
    // The 5 s of Undo are over first: the removal is final, and the text that comes later finds no item.
    await clock.advance(by: ClipboardFeature.undoTime)
    await store.receive(\.undoExpired)
    await store.receive(\.written)
    await clock.advance(by: .seconds(5))
    await store.receive(.imageRead(uuid(0), body: "mcp server")) {
      $0.queuedWrites = []
      $0.writing = 0
      $0.readingImage = nil
    }
    #expect(try rowCount() == 0)
    await store.send(.stop)
  }

  @Test
  func copyingAnImageAgainFromAnyAppOrPinningItNeverReadsItAgainAndItsTextStays() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    let reads = readImages(store, texts: [uuid(0): "mcp server"])
    await start(store)
    let png = Data("screenshot".utf8)
    await copyImage(png, from: Self.preview, store)
    await finishReading(store)

    copy(.image(png), from: Self.preview)
    await store.receive(\.written)
    copy(.image(png), from: Self.safari)
    await store.receive(\.written)
    await store.send(.pinTapped(uuid(0)))
    await store.receive(\.written)
    await store.send(.itemTapped(uuid(0)))
    await store.receive(\.copiedAgain)
    await store.receive(\.written)
    await finishCopiedMark(store)
    await clock.advance(by: .seconds(10))

    #expect(reads.value == [uuid(0)])
    #expect(store.state.imagesToRead.isEmpty)
    #expect(store.state.readingImage == nil)
    #expect(store.state.items.count == 1)
    #expect(try searchText(uuid(0)) == "safari\nmcp server")
    #expect(await search("mcp safari", store).count == 1)
    await store.send(.stop)
  }

  @Test
  func aFailedReadLeavesTheImageFoundByItsAppOnlyAndTheNextIsStillRead() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    let reads = readImages(store, texts: [uuid(0): "first words", uuid(1): "second words"], failing: [uuid(0)])
    await start(store)
    await copyImage(Data("image a".utf8), from: Self.preview, store)
    await copyImage(Data("image b".utf8), from: Self.preview, store)
    await clock.advance(by: .seconds(1))
    await store.receive(.imageRead(uuid(0), body: nil)) {
      $0.queuedWrites = []
      $0.readingImage = uuid(1)
    }
    await finishReading(store)
    // Never tried again.
    await clock.advance(by: .seconds(10))

    #expect(reads.value == [uuid(0), uuid(1)])
    #expect(try searchText(uuid(0)) == "preview\n")
    #expect(await search("words", store).map(\.isImageForTest) == [true])
    #expect(store.state.shownItems.map(\.id) == [uuid(1)])
    #expect(await search("preview", store).count == 2)
    await store.send(.stop)
  }

  /// Exhaustive: once stopped, no read is left running and nothing waits, so nothing more comes.
  @Test
  func stoppingCancelsTheReadAndDropsTheImagesWaiting() async throws {
    let store = makeStore()
    let reads = readImages(store, texts: [uuid(0): "first", uuid(1): "second"])
    await start(store)
    let (pngA, pngB) = (Data("image a".utf8), Data("image b".utf8))
    copy(.image(pngA))
    await store.receive(\.copied)
    let a = imageItem(pngA, id: 0)
    await store.receive(\.imageSaved) {
      $0.items = [a]
      $0.queuedWrites = [.insert(a)]
      $0.writing = 1
      $0.readingImage = a.id
    }
    await store.receive(\.written) {
      $0.queuedWrites = []
      $0.writing = 0
    }
    copy(.image(pngB))
    await store.receive(\.copied)
    let b = imageItem(pngB, id: 1)
    await store.receive(\.imageSaved) {
      $0.items = [b, a]
      $0.queuedWrites = [.insert(b)]
      $0.writing = 1
      $0.imagesToRead = [b.id]
    }
    await store.receive(\.written) {
      $0.queuedWrites = []
      $0.writing = 0
    }

    await store.send(.stop) {
      $0.imagesToRead = []
      $0.readingImage = nil
    }
    await clock.advance(by: .seconds(10))
    // On again, the history is loaded already: only watching starts, and nothing is read.
    await store.send(.start)
    await clock.advance(by: .seconds(10))
    await store.send(.stop)
    #expect(reads.value == [a.id])
    #expect(try searchText(a.id) == "terminal\n")
    #expect(try searchText(b.id) == "terminal\n")
  }

  @Test
  func aSessionThatKeepsTheHistoryInMemoryReadsNoImage() async throws {
    try await database.write { db in
      try db.execute(sql: "CREATE TABLE clipboard_item (id TEXT PRIMARY KEY)")
    }
    let store = makeStore()
    store.exhaustivity = .off
    let reads = readImages(store, texts: [uuid(0): "mcp server"])
    await store.send(.start)
    await store.receive(\.loadFailed)
    copy(.image(Data("screenshot".utf8)), from: Self.preview)
    await store.receive(\.imageSaved)
    await clock.advance(by: .seconds(10))

    #expect(store.state.items.count == 1)
    #expect(store.state.imagesToRead.isEmpty)
    #expect(store.state.readingImage == nil)
    #expect(reads.value.isEmpty)
    #expect(await search("mcp", store).isEmpty)
    #expect(await search("preview", store).count == 1)
    await store.send(.stop)
  }

  @Test
  func theLoadKeepsTheTextOfAnImageRowItCompletes() async throws {
    // An image row with no size, as one whose file was missing at a launch, holding the text read from it.
    let image = ClipboardItem(
      id: uuid(5), content: .image(fileName: "Image.png"), source: Self.preview, copiedAt: now.value,
      fingerprint: "image:5", byteSize: 0
    )
    try saveRows([image])
    try await database.write { db in
      try db.execute(
        sql: "UPDATE clipboard_item SET searchText = 'preview' || char(10) || 'mcp server' WHERE id = ?",
        arguments: [image.id.uuidString]
      )
    }
    // Its file is still missing: the load completes the row again, as at every launch.
    let file = try #require(image.imageURL)
    missingFiles.setValue([file])
    let store = makeStore()
    store.exhaustivity = .off
    await store.send(.start)
    await store.receive(\.loaded)

    #expect(store.state.items.map(\.id) == [image.id])
    #expect(try searchText(image.id) == "preview\nmcp server")
    #expect(await search("mcp", store) == [image.content])
    await store.send(.stop)
  }

  @Test
  func anImagesTextLandsAfterItsInsertWhileTheDatabaseIsBusy() async throws {
    let failure = LockIsolated<ResultCode?>(nil)
    try failWrites(failure)
    let store = makeStore()
    store.exhaustivity = .off
    _ = readImages(store, texts: [uuid(0): "mcp server"], delay: .milliseconds(500))
    await start(store)

    // Busy as the image is copied: its insert waits 1 s to be written again, and its text, read meanwhile, waits
    // behind it.
    failure.setValue(.SQLITE_BUSY)
    copy(.image(Data("screenshot".utf8)), from: Self.preview)
    await store.receive(\.imageSaved)
    await store.receive(\.written)
    await clock.advance(by: .milliseconds(500))
    await store.receive(\.imageRead)
    let item = try #require(store.state.items.first)
    #expect(store.state.queuedWrites == [.insert(item), .text(item.id, body: "mcp server")])
    #expect(try rowCount() == 0)

    failure.setValue(nil)
    await clock.advance(by: .milliseconds(500))
    await store.receive(\.written)
    #expect(store.state.queuedWrites.isEmpty)
    #expect(try searchText(item.id) == "preview\nmcp server")
    #expect(await search("mcp", store) == [item.content])
    await store.send(.stop)
  }
}
