import ComposableArchitecture
import Foundation
import GRDB
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureClipboard

@MainActor
struct ClipboardFeatureTests {
  let clock = TestClock()
  let database = VortexDatabase.inMemory()
  let now = LockIsolated(Date(timeIntervalSinceReferenceDate: 800_000_000))
  let copies = AsyncStream.makeStream(of: PasteboardCopy.self)
  let written = LockIsolated<[PasteboardContent]>([])
  /// The same writes with the secret flag and the source they were given.
  let writes = LockIsolated<[Write]>([])
  let savedFiles = LockIsolated<[URL]>([])
  let removedFiles = LockIsolated<[URL]>([])
  let missingFiles = LockIsolated<Set<URL>>([])

  static let terminal = AppInfo(bundleID: "com.apple.Terminal", name: "Terminal")
  static let passwords = AppInfo(bundleID: "com.example.passwords", name: "Passwords")

  struct Write: Equatable, Sendable {
    var content: PasteboardContent
    var isConcealed: Bool
    var source: AppInfo?
  }

  func makeStore(_ state: ClipboardFeature.State = ClipboardFeature.State()) -> TestStoreOf<ClipboardFeature> {
    TestStore(initialState: state) {
      ClipboardFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.database = database
      $0.date = DateGenerator { [now] in now.value }
      $0.uuid = .incrementing
      $0.pasteboardClient.copies = { [copies] in copies.stream }
      $0.pasteboardClient.write = { [written, writes] content, isConcealed, source in
        written.withValue { $0.append(content) }
        writes.withValue { $0.append(Write(content: content, isConcealed: isConcealed, source: source)) }
      }
      $0.appsClient.running = { [] }
      $0.fileClient.write = { [savedFiles] _, url in savedFiles.withValue { $0.append(url) } }
      $0.fileClient.read = { _ in Data([1, 2, 3]) }
      $0.fileClient.contents = { _ in [] }
      $0.fileClient.remove = { [removedFiles] url in removedFiles.withValue { $0.append(url) } }
      $0.fileClient.info = { [missingFiles] url in
        missingFiles.value.contains(url) ? nil : FileInfo(size: 1, isDirectory: false)
      }
    }
  }

  /// Starts the store on an empty history and lets it watch the pasteboard.
  func start(_ store: TestStoreOf<ClipboardFeature>) async {
    await store.send(.start)
    await store.receive(\.loaded) { $0.isLoaded = true }
  }

  func copy(
    _ content: PasteboardContent,
    from source: AppInfo? = terminal,
    concealed: Bool = false,
    frontApps: Set<String> = []
  ) {
    now.withValue { $0 += 60 }
    copies.continuation.yield(PasteboardCopy(content: content, isConcealed: concealed, source: source, frontApps: frontApps))
  }

  /// Lets the "Copied" mark run out, so no effect is left running.
  func finishCopiedMark(_ store: TestStoreOf<ClipboardFeature>) async {
    await clock.advance(by: .seconds(1.2))
    await store.receive(\.copiedMarkElapsed)
  }

  func savedHistory() throws -> [ClipboardItem] {
    try database.read(ClipboardItem.fetchAllReadable).sorted(by: ClipboardFeature.displayOrder)
  }

  func uuid(_ value: Int) -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012x", value))")!
  }

  // MARK: - Recording

  @Test
  func copiesAreKeptNewestFirstAndSaved() async throws {
    let store = makeStore()
    await start(store)

    copy(.text("SELECT * FROM orders"))
    await store.receive(\.copied) {
      $0.items = [ClipboardItem(id: uuid(0), content: .text("SELECT * FROM orders"), source: Self.terminal,
                                copiedAt: now.value, fingerprint: ClipboardCopy.fingerprint(of: .text("SELECT * FROM orders")))]
    }
    let link = URL(string: "https://github.com/OrtexIsArtem/vortex")!
    copy(.link(link))
    await store.receive(\.copied) {
      $0.items.insert(
        ClipboardItem(id: uuid(1), content: .link(link), source: Self.terminal,
                      copiedAt: now.value, fingerprint: ClipboardCopy.fingerprint(of: .link(link))),
        at: 0
      )
    }
    await store.send(.stop)
    await store.finish()
    #expect(try savedHistory() == store.state.items.elements)
  }

  @Test
  func copyingTheSameAgainMovesItUp() async {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text("one"))
    await store.receive(\.copied)
    copy(.text("two"))
    await store.receive(\.copied)
    copy(.text("one"), from: Self.passwords)
    await store.receive(\.copied)
    #expect(store.state.items.map(\.content) == [.text("one"), .text("two")])
    #expect(store.state.items.first?.source == Self.passwords)
    await store.send(.stop)
  }

  @Test
  func keepsTenItemsPlusPinnedOnes() async {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text("pinned"))
    await store.receive(\.copied)
    await store.send(.pinTapped(uuid(0)))
    for index in 1...11 {
      copy(.text("item \(index)"))
      await store.receive(\.copied)
    }
    #expect(store.state.items.count == 11)
    #expect(store.state.items.first?.content == .text("pinned"))
    #expect(store.state.items.last?.content == .text("item 2"))
    await store.send(.stop)
  }

  @Test
  func ignoredAppsAreSkipped() async {
    let store = makeStore()
    await start(store)
    await store.send(.ignoreAppTapped(Self.passwords)) {
      $0.$settings.withLock { $0.ignoredApps = [Self.passwords] }
    }
    copy(.text("secret"), from: Self.passwords)
    await store.receive(\.copied)
    // Copied in a password panel that handed the focus back before the pasteboard was checked.
    copy(.text("secret 2"), from: Self.terminal, frontApps: [Self.passwords.bundleID, Self.terminal.bundleID])
    await store.receive(\.copied)
    #expect(store.state.items.isEmpty)
    await store.send(.stopIgnoringAppTapped(bundleID: Self.passwords.bundleID)) {
      $0.$settings.withLock { $0.ignoredApps = [] }
    }
    await store.send(.stop)
  }

  @Test
  func secretsAreKeptInMemoryOnly() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text("hunter2"), concealed: true)
    await store.receive(\.copied)
    copy(.text("visible"))
    await store.receive(\.copied)
    copy(.image(Data([1])), concealed: true)
    await store.receive(\.copied)
    await store.send(.stop)
    await store.finish()
    #expect(store.state.items.map(\.content) == [.text("visible"), .text("hunter2")])
    #expect(try savedHistory().map(\.content) == [.text("visible")])
    #expect(savedFiles.value.isEmpty)
  }

  @Test
  func concealedItemsHideAgainWhenTheWindowOpens() async {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text("hunter2"), concealed: true)
    await store.receive(\.copied)
    #expect(store.state.items.first?.isConcealed == true)
    await store.send(.revealTapped(uuid(0))) { $0.revealed = [uuid(0)] }
    await store.send(.tabShown) { $0.revealed = [] }
    await store.send(.stop)
  }

  // MARK: - Images

  @Test
  func imagesAppearOnceTheirFileIsWritten() async {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.image(Data([0x89, 0x50])))
    await store.receive(\.copied)
    #expect(store.state.items.isEmpty)
    await store.receive(\.imageSaved)
    let item = store.state.items.first
    #expect(item?.imageURL?.lastPathComponent.hasPrefix("Image ") == true)
    #expect(savedFiles.value == [item?.imageURL])
    await store.send(.deleteTapped(uuid(0)))
    await store.send(.stop)
    await store.finish()
    #expect(removedFiles.value == [item?.imageURL?.deletingLastPathComponent()])
  }

  // MARK: - Actions

  @Test
  func clickCopiesAgainAndMovesTheItemUp() async {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text("first"))
    await store.receive(\.copied)
    copy(.text("second"))
    await store.receive(\.copied)

    now.withValue { $0 += 60 }
    await store.send(.itemTapped(uuid(0)))
    await store.receive(\.copiedAgain) { $0.justCopied = uuid(0) }
    #expect(store.state.items.map(\.content) == [.text("first"), .text("second")])
    await clock.advance(by: .seconds(1.2))
    await store.receive(\.copiedMarkElapsed) { $0.justCopied = nil }
    #expect(written.value == [.text("first")])
    await store.send(.stop)
  }

  @Test
  func clearKeepsPinnedItems() async {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text("keep"))
    await store.receive(\.copied)
    copy(.text("drop"))
    await store.receive(\.copied)
    await store.send(.pinTapped(uuid(0)))
    await store.send(.clearTapped)
    #expect(store.state.items.map(\.content) == [.text("keep")])
    await store.send(.stop)
  }

  @Test
  func missingFilesAreMarkedWhenTheTabIsShown() async {
    let gone = URL(fileURLWithPath: "/tmp/gone.zip")
    missingFiles.setValue([gone])
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.files([gone]))
    await store.receive(\.copied)
    await store.send(.tabShown)
    await store.receive(\.unavailableChecked) { $0.unavailable = [uuid(0)] }
    await store.send(.itemTapped(uuid(0)))
    #expect(written.value.isEmpty)
    await store.send(.stop)
  }

  // MARK: - Dropping on the clipboard

  @Test
  func somethingDroppedIsCopiedAndJoinsTheHistory() async {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    await store.send(.dropped([.text("release notes")]))
    await store.receive(\.copied)
    #expect(written.value == [.text("release notes")])
    #expect(store.state.items.first?.content == .text("release notes"))
    await store.send(.stop)
  }

  @Test
  func droppedFilesAreCopiedTogetherOtherwiseTheFirstThing() {
    let ipa = URL(fileURLWithPath: "/tmp/a.ipa")
    let apk = URL(fileURLWithPath: "/tmp/b.apk")
    let link = URL(string: "https://example.com")!
    #expect(ClipboardFeature.copiedContent(of: [.file(ipa), .text("x"), .file(apk)]) == .files([ipa, apk]))
    #expect(ClipboardFeature.copiedContent(of: [.image(Data([1]), fileExtension: "jpeg"), .link(link)]) == .link(link))
    #expect(ClipboardFeature.copiedContent(of: [.image(Data([1]), fileExtension: "PNG")]) == .image(Data([1])))
    #expect(ClipboardFeature.copiedContent(of: [.image(Data([1]), fileExtension: "jpeg")]) == nil)
  }

  @Test
  func droppedExternalFilesJoinTheHistoryAsOneRow() async {
    let ipa = URL(fileURLWithPath: "/tmp/a.ipa")
    let apk = URL(fileURLWithPath: "/tmp/b.apk")
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    await store.send(.dropped([.file(ipa), .file(apk)]))
    await store.receive(\.copied)
    #expect(store.state.items.map(\.content) == [.files([ipa, apk])])
    #expect(written.value == [.files([ipa, apk])])
    await store.send(.stop)
  }

  @Test
  func externalFilesWinOverAnOwnImageDroppedWithThem() async {
    let ipa = URL(fileURLWithPath: "/tmp/a.ipa")
    let shelfCopy = DataFolder.url.appending(path: "Shelf/ABC/Image 2026-10-06 at 13.40.12.png")
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    await store.send(.dropped([.file(shelfCopy), .file(ipa)]))
    await store.receive(\.copied)
    #expect(store.state.items.map(\.content) == [.files([ipa])])
    #expect(written.value == [.files([ipa])])
    await store.send(.stop)
  }

  @Test
  func droppingWhatTheHistoryHoldsCopiesThatItemAgain() async {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text("one"), from: Self.passwords)
    await store.receive(\.copied)
    copy(.text("two"))
    await store.receive(\.copied)
    now.withValue { $0 += 60 }

    await store.send(.dropped([.text("one")]))
    await store.receive(\.copiedAgain)
    // No new row: the old one moves up, shows the mark and goes to the pasteboard with its own source.
    #expect(store.state.items.map(\.content) == [.text("one"), .text("two")])
    #expect(store.state.justCopied == uuid(0))
    #expect(writes.value == [Write(content: .text("one"), isConcealed: false, source: Self.passwords)])
    await finishCopiedMark(store)
    await store.send(.stop)
  }

  @Test
  func aSecretDroppedBackStaysASecretAndOffTheDisk() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text("hunter2"), concealed: true)
    await store.receive(\.copied)

    // Pressing a secret row and moving a few points drags its text; here it lands on the clipboard again.
    await store.send(.dropped([.text("hunter2")]))
    await store.receive(\.copiedAgain)
    #expect(store.state.items.count == 1)
    #expect(store.state.items.first?.isConcealed == true)
    #expect(writes.value == [Write(content: .text("hunter2"), isConcealed: true, source: Self.terminal)])
    await finishCopiedMark(store)
    await store.send(.stop)
    await store.finish()
    #expect(try savedHistory().isEmpty)
  }

  @Test
  func anImageRowDroppedBackIsCopiedAgainNotKeptAsAFile() async throws {
    let png = Data([0x89, 0x50])
    let store = makeStore()
    store.exhaustivity = .off
    // Reading the item's file gives back the PNG that was saved there.
    store.dependencies.fileClient.read = { _ in png }
    await start(store)
    copy(.image(png))
    await store.receive(\.imageSaved)
    let file = try #require(store.state.items.first?.imageURL)
    #expect(file.path.hasPrefix(ClipboardItem.imagesFolder.path))

    await store.send(.dropped([.file(file)]))
    await store.receive(\.copiedAgain)
    #expect(store.state.items.count == 1)
    #expect(written.value == [.image(png)])
    await finishCopiedMark(store)
    await store.send(.stop)
  }

  @Test
  func anOwnPNGDroppedIsCopiedAsAnImageNotAsAFile() async throws {
    let png = Data([0x89, 0x50, 0x4E])
    // An image the shelf saved as a copy: the shelf deletes its file together with its item.
    let shelfCopy = DataFolder.url.appending(path: "Shelf/ABC/Image 2026-10-06 at 13.40.12.png")
    let store = makeStore()
    store.exhaustivity = .off
    store.dependencies.fileClient.read = { _ in png }
    await start(store)
    await store.send(.dropped([.file(shelfCopy)]))
    await store.receive(\.imageSaved)
    let item = try #require(store.state.items.first)
    #expect(store.state.items.count == 1)
    #expect(item.imageURL != nil)
    #expect(written.value == [.image(png)])
    #expect(savedFiles.value == [item.imageURL])
    await store.send(.stop)
    await store.finish()
  }

  @Test
  func anOwnFileThatIsNotAPNGIsLeftOut() async {
    let jpeg = DataFolder.url.appending(path: "Shelf/ABC/Image 2026-10-06 at 13.40.12.jpeg")
    let reads = LockIsolated<[URL]>([])
    let store = makeStore()
    store.exhaustivity = .off
    store.dependencies.fileClient.read = { [reads] url in
      reads.withValue { $0.append(url) }
      return Data([1])
    }
    await start(store)
    await store.send(.dropped([.file(jpeg)]))
    await store.send(.stop)
    await store.finish()
    #expect(store.state.items.isEmpty)
    #expect(written.value.isEmpty)
    // Nothing is made of it, so it is not even read.
    #expect(reads.value.isEmpty)
  }

  @Test
  func filesInTheDataFolderAreVortexsOwn() {
    #expect(ClipboardFeature.isOwnFile(ClipboardItem.imagesFolder.appending(path: "ABC/Image.png")))
    #expect(ClipboardFeature.isOwnFile(DataFolder.url.appending(path: "Shelf/ABC/Image.png")))
    #expect(!ClipboardFeature.isOwnFile(URL(fileURLWithPath: "/tmp/Image.png")))
    // A neighbor whose name only starts the same is not inside the folder.
    #expect(!ClipboardFeature.isOwnFile(URL(fileURLWithPath: DataFolder.url.path + "2/Image.png")))
  }

  @Test
  func droppedFilesThatWereMissingEarlierAreCopiedAndNoLongerMissing() async {
    let rebuilt = URL(fileURLWithPath: "/tmp/app-release.apk")
    missingFiles.setValue([rebuilt])
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.files([rebuilt]))
    await store.receive(\.copied)
    await store.send(.tabShown)
    await store.receive(\.unavailableChecked) { $0.unavailable = [uuid(0)] }

    // The build is made again at the same path and dragged here: it exists now, whatever the last check said.
    missingFiles.setValue([])
    await store.send(.dropped([.file(rebuilt)]))
    await store.receive(\.copiedAgain)
    #expect(store.state.items.count == 1)
    #expect(store.state.unavailable.isEmpty)
    #expect(written.value == [.files([rebuilt])])
    await finishCopiedMark(store)
    await store.send(.stop)
  }

  // MARK: - Saving

  @Test
  func historySurvivesARelaunch() async throws {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text("kept"))
    await store.receive(\.copied)
    await store.send(.pinTapped(uuid(0)))
    await store.send(.stop)
    await store.finish()

    let relaunched = makeStore()
    relaunched.exhaustivity = .off
    await relaunched.send(.start)
    await relaunched.receive(\.loaded)
    #expect(relaunched.state.items.map(\.content) == [.text("kept")])
    #expect(relaunched.state.items.first?.isPinned == true)
    await relaunched.send(.stop)
  }

  @Test
  func anUnreadableHistoryIsLeftAloneAndCopiesStillWork() async throws {
    try await database.write { db in
      try db.execute(sql: "CREATE TABLE clipboard_item (id TEXT PRIMARY KEY)")
    }
    let store = makeStore()
    store.exhaustivity = .off
    await store.send(.start)
    await store.receive(\.loadFailed)
    copy(.text("kept for this session"))
    await store.receive(\.copied)
    #expect(store.state.items.map(\.content) == [.text("kept for this session")])
    #expect(!store.state.savesToDisk)
    await store.send(.stop)
  }

  @Test
  func imageFoldersWithoutARowAreRemovedAtStart() async throws {
    let orphan = ClipboardItem.imagesFolder.appending(path: "ORPHAN")
    let store = makeStore()
    store.dependencies.fileClient.contents = { _ in [orphan] }
    await start(store)
    await store.send(.stop)
    #expect(removedFiles.value == [orphan])
  }

  @Test
  func rowsOfANewerVersionSurviveSaving() async throws {
    try ClipboardItem.migrator.migrate(database)
    try await database.write { db in
      try db.execute(sql: """
        INSERT INTO clipboard_item (id, content, copiedAt, isPinned, isConcealed, fingerprint)
        VALUES ('FUTURE', '{"future":{}}', '2026-10-04 10:00:00.000', 1, 0, 'x')
        """)
    }
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text("new"))
    await store.receive(\.copied)
    await store.send(.stop)
    await store.finish()
    #expect(try await database.read { try String.fetchAll($0, sql: "SELECT id FROM clipboard_item ORDER BY id") } == [
      "00000000-0000-0000-0000-000000000000", "FUTURE",
    ])
  }

  @Test
  func unreadableRowsAreSkipped() throws {
    try ClipboardItem.migrator.migrate(database)
    try database.write { db in
      try db.execute(sql: """
        INSERT INTO clipboard_item (id, content, copiedAt, isPinned, isConcealed, fingerprint)
        VALUES ('BAD', '{"future":{}}', '2026-10-04 10:00:00.000', 0, 0, 'x')
        """)
    }
    #expect(try database.read(ClipboardItem.fetchAllReadable).isEmpty)
  }
}
