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
  let savedFiles = LockIsolated<[URL]>([])
  let removedFiles = LockIsolated<[URL]>([])
  let missingFiles = LockIsolated<Set<URL>>([])

  static let terminal = AppInfo(bundleID: "com.apple.Terminal", name: "Terminal")
  static let passwords = AppInfo(bundleID: "com.example.passwords", name: "Passwords")

  func makeStore(_ state: ClipboardFeature.State = ClipboardFeature.State()) -> TestStoreOf<ClipboardFeature> {
    TestStore(initialState: state) {
      ClipboardFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.database = database
      $0.date = DateGenerator { [now] in now.value }
      $0.uuid = .incrementing
      $0.pasteboardClient.copies = { [copies] in copies.stream }
      $0.pasteboardClient.write = { [written] content, _ in written.withValue { $0.append(content) } }
      $0.fileClient.write = { [savedFiles] _, url in savedFiles.withValue { $0.append(url) } }
      $0.fileClient.read = { _ in Data([1, 2, 3]) }
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

  func copy(_ content: PasteboardContent, from source: AppInfo? = terminal, concealed: Bool = false) {
    now.withValue { $0 += 60 }
    copies.continuation.yield(PasteboardCopy(content: content, isConcealed: concealed, source: source))
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
    #expect(store.state.items.isEmpty)
    await store.send(.stopIgnoringAppTapped(bundleID: Self.passwords.bundleID)) {
      $0.$settings.withLock { $0.ignoredApps = [] }
    }
    await store.send(.stop)
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
    await store.send(.itemTapped(uuid(0))) { $0.justCopied = uuid(0) }
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
