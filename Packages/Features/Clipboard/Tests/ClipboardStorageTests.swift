import ComposableArchitecture
import Foundation
import GRDB
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureClipboard

/// The saved history: one row per change, in the order the changes were made; long texts kept in memory by their start.
extension ClipboardFeatureTests {
  /// 6,001 bytes in UTF-8: its 4,096-byte start ends between two letters, at 4,095 bytes.
  static let longText = "a" + String(repeating: "й", count: 3_000)
  static let longTextStart = "a" + String(repeating: "й", count: 2_047)

  func row(_ id: UUID) throws -> Row? {
    try database.read { db in
      try Row.fetchOne(db, sql: "SELECT * FROM clipboard_item WHERE id = ?", arguments: [id.uuidString])
    }
  }

  func rowCount(_ condition: String = "1") throws -> Int {
    try database.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM clipboard_item WHERE \(condition)") ?? 0 }
  }

  // MARK: - Order

  /// A change that writes nothing, standing for a batch being written.
  static let inFlight = HistoryWrite.delete([], folders: [])

  /// A loaded history while a batch of writes is being written, as after any change.
  func writingState(_ items: [ClipboardItem] = []) -> ClipboardFeature.State {
    var state = ClipboardFeature.State()
    state.items = IdentifiedArray(uniqueElements: items)
    state.isLoaded = true
    state.queuedWrites = [Self.inFlight]
    state.writing = 1
    return state
  }

  @Test
  func anInsertFollowedAtOnceByADeleteLeavesNoRow() async throws {
    try ClipboardItem.migrator.migrate(database)
    let store = makeStore(writingState())
    let typo = item("typo", id: 0, copiedAt: now.value)
    await store.send(.copied(ClipboardCopy(PasteboardCopy(content: .text("typo"), source: Self.terminal)))) {
      $0.items = [typo]
      $0.queuedWrites = [Self.inFlight, .insert(typo)]
    }
    await store.send(.deleteTapped(typo.id)) {
      $0.items = []
      $0.queuedWrites = [Self.inFlight, .insert(typo), .delete([typo.id], folders: [])]
    }
    // The batch being written is in: the queued writes go next, together and in order.
    await store.send(.written(done: 1, previews: [:], failed: false)) {
      $0.queuedWrites = [.insert(typo), .delete([typo.id], folders: [])]
      $0.writing = 2
    }
    await store.receive(\.written) {
      $0.queuedWrites = []
      $0.writing = 0
    }
    #expect(try rowCount() == 0)
  }

  @Test
  func pinThenUnpinAtOnceLeaveItUnpinned() async throws {
    let one = item("one", id: 0, copiedAt: now.value)
    try saveRows([one])
    var pinned = one
    pinned.isPinned = true
    let store = makeStore(writingState([one]))
    await store.send(.pinTapped(one.id)) {
      $0.items = [pinned]
      $0.queuedWrites = [Self.inFlight, .update(pinned)]
    }
    await store.send(.pinTapped(one.id)) {
      $0.items = [one]
      $0.queuedWrites = [Self.inFlight, .update(pinned), .update(one)]
    }
    await store.send(.written(done: 1, previews: [:], failed: false)) {
      $0.queuedWrites = [.update(pinned), .update(one)]
      $0.writing = 2
    }
    await store.receive(\.written) {
      $0.queuedWrites = []
      $0.writing = 0
    }
    #expect(try savedHistory().map(\.isPinned) == [false])
  }

  @Test
  func aLongTextStaysWholeUntilItsRowIsWritten() async throws {
    try ClipboardItem.migrator.migrate(database)
    let store = makeStore(writingState())
    store.exhaustivity = .off
    await store.send(.copied(ClipboardCopy(PasteboardCopy(content: .text(Self.longText), source: Self.terminal))))
    #expect(store.state.items.first?.content == .text(Self.longText))
    #expect(store.state.items.first?.isTruncated == false)
    await store.send(.written(done: 1, previews: [:], failed: false))
    await store.receive(\.written)
    #expect(store.state.items.first?.content == .text(Self.longTextStart))
    #expect(store.state.items.first?.isTruncated == true)
  }

  @Test(arguments: [(10, false), (10_000, false), (10, true), (10_000, true)])
  func aCopyChangesOneRowWhateverTheHistorySize(historySize: Int, pinned: Bool) async throws {
    // Copied over the last hours; pinned items don't count toward the 10,000.
    let first = now.value
    try saveRows((0..<historySize).map { index in
      item("item \(index)", id: 100_000 + index, copiedAt: first - Double(index), isPinned: pinned)
    })
    let store = makeStore()
    store.exhaustivity = .off
    store.timeout = .seconds(60)
    let loading = ContinuousClock.now
    await store.send(.start)
    await store.receive(\.loaded)
    let loaded = ContinuousClock.now - loading
    #expect(store.state.items.count == historySize)

    func changes() throws -> Int { try database.read { $0.totalChangesCount } }
    let beforeInsert = try changes()
    copy(.text("new"))
    await store.receive(\.copied)
    await store.receive(\.written)
    let beforeBump = try changes()
    // Copied again: it moves up.
    copy(.text("item \(historySize / 2)"))
    await store.receive(\.copied)
    await store.receive(\.written)
    let afterBump = try changes()
    await store.send(.pinTapped(uuid(0)))
    await store.receive(\.written)
    let afterPin = try changes()
    // The 10,001st unpinned item pushes the oldest out: its row goes in the same batch.
    #expect(beforeBump - beforeInsert == (!pinned && historySize == ClipboardFeature.maxItems ? 2 : 1))
    #expect(afterBump - beforeBump == 1)
    #expect(afterPin - afterBump == 1)
    print("""
      history of \(historySize) \(pinned ? "pinned" : "unpinned") items: rows changed by a new copy \
      \(beforeBump - beforeInsert), a copy again \(afterBump - beforeBump), a pin \(afterPin - afterBump); \
      loaded in \(loaded)
      """)
    await store.send(.stop)
  }

  /// No sort on a copy: every change puts the item where `displayOrder` has it.
  @Test
  func theHistoryStaysPinnedFirstNewestFirst() async {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    func expectOrdered() {
      #expect(store.state.items.elements == store.state.items.elements.sorted(by: ClipboardFeature.displayOrder))
    }
    for index in 0..<6 {
      copy(.text("item \(index)"))
      await store.receive(\.copied)
      expectOrdered()
    }
    await store.send(.pinTapped(uuid(2)))
    expectOrdered()
    await store.send(.pinTapped(uuid(4)))
    expectOrdered()
    copy(.text("item 0"))
    await store.receive(\.copied)
    expectOrdered()
    copy(.text("item 4"))
    await store.receive(\.copied)
    expectOrdered()
    #expect(store.state.items.map(\.content) == [
      .text("item 4"), .text("item 2"), .text("item 0"), .text("item 5"), .text("item 3"), .text("item 1"),
    ])
    await store.send(.pinTapped(uuid(2)))
    expectOrdered()
    await store.send(.stop)
  }

  // MARK: - Long texts

  @Test
  func aLongTextIsKeptByItsStartOnceSavedAndCopiedAgainWhole() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text(Self.longText))
    await store.receive(\.copied)
    await store.receive(\.written)
    let item = try #require(store.state.items.first)
    #expect(item.content == .text(Self.longTextStart))
    #expect(item.isTruncated)
    #expect(item.byteSize == 6_001)
    #expect(Self.longTextStart.utf8.count == 4_095)

    await store.send(.itemTapped(item.id))
    await store.receive(\.copiedAgain)
    #expect(written.value == [.text(Self.longText)])
    await finishCopiedMark(store)
    await store.send(.stop)
  }

  @Test
  func aLongTextDragsOnceItsWholeTextIsRead() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text(Self.longText))
    await store.receive(\.copied)
    await store.receive(\.written)
    let item = try #require(store.state.items.first)
    #expect(item.dragItems(isRevealed: false).isEmpty)

    await store.send(.itemHovered(item.id))
    await store.receive(\.wholeTextRead)
    let wholeText = try #require(store.state.wholeText)
    #expect(wholeText.id == item.id)
    #expect(item.dragItems(isRevealed: false, wholeText: wholeText.text) == [.text(Self.longText)])
    // Read once: hovering again reads nothing.
    await store.send(.itemHovered(item.id))
    // A deleted item's text goes with it.
    await store.send(.deleteTapped(item.id))
    #expect(store.state.wholeText == nil)
    await store.send(.stop)
  }

  @Test
  func aLongTextStaysWholeOnDiskThroughPinUnpinCopyAgainAndUndo() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text(Self.longText))
    await store.receive(\.copied)
    await store.receive(\.written)
    let id = try #require(store.state.items.first?.id)
    #expect(store.state.items[id: id]?.isTruncated == true)
    await store.send(.pinTapped(id))
    await store.receive(\.written)
    await store.send(.pinTapped(id))
    await store.receive(\.written)
    await store.send(.itemTapped(id))
    await store.receive(\.copiedAgain)
    await store.receive(\.written)
    await store.send(.clearTapped)
    await store.send(.undoTapped)
    // Copied again from another app: the app's line of the search text changes, the rest stays.
    copy(.text(Self.longText), from: Self.safari)
    await store.receive(\.copied)
    await store.receive(\.written)
    await finishCopiedMark(store)
    await store.send(.stop)
    await store.finish()
    #expect(store.state.items[id: id]?.content == .text(Self.longTextStart))
    let saved = try #require(try row(id))
    #expect(try await database.read { db in try ClipboardItem.wholeText(of: id, db) } == Self.longText)
    #expect(saved["preview"] as String? == Self.longTextStart)
    #expect(saved["searchText"] as String? == "safari\n" + Self.longText)
    #expect(saved["byteSize"] as Int? == Self.longText.utf8.count)
  }

  @Test
  func aReadThatEndsLateNeverReplacesTheWholeTextOfTheCardUnderThePointer() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    let other = "b" + Self.longText
    copy(.text(Self.longText))
    await store.receive(\.copied)
    await store.receive(\.written)
    copy(.text(other))
    await store.receive(\.copied)
    await store.receive(\.written)
    let (y, x) = (store.state.items[0], store.state.items[1])
    await store.send(.itemHovered(x.id))
    await store.receive(\.wholeTextRead)
    // The pointer goes over Y, whose read starts, and back to X before it ends.
    await store.send(.itemHovered(y.id))
    await store.send(.itemHovered(x.id))
    await store.send(.wholeTextRead(y.id, other))
    #expect(store.state.wholeText?.id == x.id)
    #expect(x.dragItems(isRevealed: false, wholeText: store.state.wholeText?.text) == [.text(Self.longText)])
    await store.send(.stop)
  }

  @Test
  func aLongTextLoadsWithItsStartOnlyAndItsWholeTextUnread() async throws {
    let long = item(Self.longText, id: 5, copiedAt: now.value)
    try saveRows([long])
    let saved = try #require(try row(long.id))
    #expect(saved["preview"] as String? == Self.longTextStart)
    // Its whole text is never decoded at launch: broken here, the item still loads.
    try await database.write { db in
      try db.execute(sql: "UPDATE clipboard_item SET content = 'not JSON' WHERE id = ?", arguments: [long.id.uuidString])
    }
    let store = makeStore()
    store.exhaustivity = .off
    await store.send(.start)
    await store.receive(\.loaded)
    let loaded = try #require(store.state.items.first)
    #expect(loaded.content == .text(Self.longTextStart))
    #expect(loaded.isTruncated)
    #expect(loaded.byteSize == 6_001)
    await store.send(.stop)
  }

  /// A history saved by Vortex 0.1.2 (the v1 table): the first launch works out the new columns, an image's size from
  /// its file.
  @Test
  func rowsSavedBeforeVersionTwoAreCompletedAtLoad() async throws {
    try ClipboardItem.migrator.migrate(database, upTo: "clipboard.v1")
    let link = URL(string: "https://uk.wikipedia.org/wiki/%D0%9A%D0%B8%D1%97%D0%B2")!
    let files = [URL(fileURLWithPath: "/tmp/Звіт.pdf")]
    let contents: [ClipboardItem.Content] = [.text(Self.longText), .link(link), .image(fileName: "Image.png"), .files(files)]
    // As Vortex 0.1.2 wrote them: JSON with sorted keys.
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let oldRows: [StatementArguments] = try contents.enumerated().map { index, content in
      [
        uuid(index).uuidString,
        String(decoding: try encoder.encode(content), as: UTF8.self),
        String(decoding: try encoder.encode(Self.terminal), as: UTF8.self),
        now.value - Double(index),
        ["text:x", "link:x", "image:x", "files:x"][index],
      ]
    }
    try await database.write { db in
      for arguments in oldRows {
        try db.execute(
          sql: """
            INSERT INTO clipboard_item (id, content, source, copiedAt, isPinned, isConcealed, fingerprint)
            VALUES (?, ?, ?, ?, 0, 0, ?)
            """,
          arguments: arguments
        )
      }
    }
    let store = makeStore()
    store.exhaustivity = .off
    store.dependencies.fileClient.info = { url in
      url.lastPathComponent == "Image.png" ? FileInfo(size: 123_456, isDirectory: false) : nil
    }
    await store.send(.start)
    await store.receive(\.loaded)

    #expect(store.state.items.map(\.byteSize) == [6_001, link.absoluteString.utf8.count, 123_456, "/tmp/Звіт.pdf".utf8.count])
    #expect(store.state.items[0].content == .text(Self.longTextStart))
    #expect(store.state.items[0].isTruncated)
    let rows = try contents.indices.map { try #require(try row(uuid($0))) }
    #expect(rows.map { $0["byteSize"] as Int } == store.state.items.map(\.byteSize))
    #expect(rows.map { $0["preview"] as String? } == [Self.longTextStart, nil, nil, nil])
    #expect(rows.map { $0["searchText"] as String } == [
      "terminal\n" + Self.longText,
      "terminal\nhttps://uk.wikipedia.org/wiki/київ",
      "terminal\n",
      "terminal\nзвіт.pdf",
    ])
    await store.send(.stop)
  }

  // MARK: - Secrets and other versions

  @Test
  func aSecretNeverHasARowAndAnItemThatTurnsSecretLosesItsRow() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text("hunter2"), from: Self.passwords, concealed: true)
    await store.receive(\.copied)
    #expect(store.state.queuedWrites.isEmpty)
    #expect(try rowCount() == 0)

    // Copied in an editor first, then the same text from a password manager, which marks it secret.
    copy(.text(Self.longText))
    await store.receive(\.copied)
    await store.receive(\.written)
    #expect(try rowCount() == 1)
    copy(.text(Self.longText), from: Self.passwords, concealed: true)
    await store.receive(\.copied)
    await store.receive(\.written)
    #expect(try rowCount() == 0)
    // Memory holds the whole text again: no row has it any more.
    let secret = try #require(store.state.items.first)
    #expect(secret.isConcealed)
    #expect(!secret.isTruncated)
    #expect(secret.content == .text(Self.longText))
    // Pinned, copied again, deleted: still never written.
    await store.send(.pinTapped(secret.id))
    await store.send(.itemTapped(secret.id))
    await store.receive(\.copiedAgain)
    #expect(written.value == [.text(Self.longText)])
    await finishCopiedMark(store)
    #expect(try rowCount() == 0)
    await store.send(.stop)
    await store.finish()
    #expect(try rowCount() == 0)
  }

  @Test
  func rowsOfANewerVersionAreNeverChangedOrDeleted() async throws {
    try ClipboardItem.migrator.migrate(database)
    try await database.write { db in
      // A kind of content this version doesn't know, and a newer kind that has a preview too.
      try db.execute(sql: """
        INSERT INTO clipboard_item (id, content, copiedAt, isPinned, isConcealed, fingerprint, byteSize, preview, searchText)
        VALUES ('00000000-0000-0000-0000-0000000000F1', '{"future":{}}', '2026-10-04 10:00:00.000', 0, 0, 'future:x', 0, NULL, ''),
          ('00000000-0000-0000-0000-0000000000F2', '{"rich":{}}', '2026-10-04 10:00:00.000', 0, 0, 'rich:x', 9000, 'start', 'x')
        """)
    }
    func futureRows() throws -> [Row] {
      try database.read { db in try Row.fetchAll(db, sql: "SELECT * FROM clipboard_item WHERE id LIKE '%F_' ORDER BY id") }
    }
    let before = try futureRows()
    // An item past the lifetime goes at launch.
    try saveRows([item("old", id: 99, copiedAt: now.value - 40 * 86_400)])
    let store = makeStore()
    store.exhaustivity = .off
    await store.send(.start)
    await store.receive(\.loaded)
    #expect(store.state.items.isEmpty)
    for index in 0..<4 {
      copy(.text("item \(index)"))
      await store.receive(\.copied)
    }
    await store.send(.pinTapped(uuid(3)))
    await store.send(.deleteTapped(uuid(2)))
    await store.send(.clearTapped)
    await clock.advance(by: ClipboardFeature.undoTime)
    await store.receive(\.undoExpired)
    await store.send(.lifetimeChanged(.week))
    await store.send(.stop)
    await store.finish()
    #expect(try futureRows() == before)
    #expect(try savedHistory().map(\.content) == [.text("item 3")])
  }

  // MARK: - Columns

  @Test
  func theStartOfALongTextIsCutBetweenCharacters() {
    #expect(ClipboardItem.preview(of: String(repeating: "a", count: 4_096)) == nil)
    #expect(ClipboardItem.preview(of: String(repeating: "a", count: 4_097)) == String(repeating: "a", count: 4_096))
    #expect(ClipboardItem.preview(of: Self.longText) == Self.longTextStart)
    // A letter with its accent is one character: the cut never falls between them.
    let accented = String(repeating: "a", count: 4_095) + "e\u{301}"
    #expect(ClipboardItem.preview(of: accented) == String(repeating: "a", count: 4_095))
  }

  @Test
  func searchTextHasTheAppFirstThenTheContentLowercased() {
    let finder = AppInfo(bundleID: "com.apple.finder", name: "Finder")
    #expect(ClipboardItem.searchText(of: .text("Привіт, Світ"), source: Self.terminal) == "terminal\nпривіт, світ")
    #expect(ClipboardItem.searchText(of: .image(fileName: "Image.png"), source: finder) == "finder\n")
    #expect(ClipboardItem.searchText(of: .text("x"), source: nil) == "\nx")
    // A name from the file system may come decomposed; search compares composed letters.
    let decomposed = "Й".decomposedStringWithCanonicalMapping
    #expect(ClipboardItem.searchText(of: .files([URL(fileURLWithPath: "/tmp/\(decomposed).txt")]), source: finder) == "finder\nй.txt")
    // Only the first 16 KB of a text.
    let big = String(repeating: "b", count: 20_000)
    #expect(ClipboardItem.searchText(of: .text(big), source: nil).utf8.count == 1 + 16_384)
  }
}
