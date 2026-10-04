import ComposableArchitecture
import Foundation
import GRDB
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureShelf

@MainActor
struct ShelfFeatureTests {
  let clock = TestClock()
  let database = VortexDatabase.inMemory()
  let now = LockIsolated(Date(timeIntervalSinceReferenceDate: 800_000_000))
  let written = LockIsolated<[URL]>([])
  let copied = LockIsolated<[URL]>([])
  let removed = LockIsolated<[URL]>([])
  let opened = LockIsolated<[URL]>([])
  let quickLooked = LockIsolated<[[URL]]>([])
  let missing = LockIsolated<Set<URL>>([])

  nonisolated static let ipa = URL(fileURLWithPath: "/Users/me/Builds/Vortex-1.4.2.ipa")
  nonisolated static let apk = URL(fileURLWithPath: "/Users/me/Builds/app-release.apk")
  nonisolated static let notes = URL(fileURLWithPath: "/Users/me/Documents/notes.txt")

  func makeStore() -> TestStoreOf<ShelfFeature> {
    let store = TestStore(initialState: ShelfFeature.State()) {
      ShelfFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.database = database
      $0.date = DateGenerator { [now] in now.value }
      $0.uuid = .incrementing
      $0.fileClient.info = { [missing] url in missing.value.contains(url) ? nil : FileInfo(size: 1_000, isDirectory: false) }
      $0.fileClient.write = { [written] _, url in written.withValue { $0.append(url) } }
      $0.fileClient.copy = { [copied] _, url in copied.withValue { $0.append(url) } }
      $0.fileClient.remove = { [removed] url in removed.withValue { $0.append(url) } }
      $0.fileClient.open = { [opened] url in opened.withValue { $0.append(url) } }
      $0.quickLookClient.toggle = { [quickLooked] urls in quickLooked.withValue { $0.append(urls) } }
      $0.quickLookClient.close = {}
    }
    store.exhaustivity = .off
    return store
  }

  func start(_ store: TestStoreOf<ShelfFeature>) async {
    await store.send(.start)
    await store.receive(\.loaded)
  }

  func uuid(_ value: Int) -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012x", value))")!
  }

  func contents(_ store: TestStoreOf<ShelfFeature>) -> [ShelfItem.Content] {
    store.state.items.map(\.content)
  }

  // MARK: - Adding

  @Test
  func droppedFilesGoOnTheShelfNewestFirst() async {
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.file(Self.ipa), .file(Self.apk)]))
    await store.receive(\.infoLoaded)
    #expect(store.state.info[uuid(0)] == FileInfo(size: 1_000, isDirectory: false))
    now.withValue { $0 += 60 }
    await store.send(.dropped([.text("release notes"), .link(URL(string: "https://example.com")!)]))
    #expect(contents(store) == [
      .text("release notes"), .link(URL(string: "https://example.com")!), .file(Self.ipa), .file(Self.apk),
    ])
    #expect(store.state.fresh.isEmpty)
    #expect(store.state.flashes == 0)
    await store.send(.stop)
  }

  @Test
  func droppingWhatIsAlreadyThereMovesItToTheFront() async {
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.file(Self.ipa), .file(Self.apk)]))
    now.withValue { $0 += 60 }
    await store.send(.dropped([.file(Self.apk), .file(Self.apk)]))
    #expect(contents(store) == [.file(Self.apk), .file(Self.ipa)])
    #expect(store.state.items.first?.addedAt == now.value)
    await store.send(.stop)
  }

  @Test
  func filesFromOutsideAreMarkedAndFlashTheNotch() async {
    let store = makeStore()
    await start(store)
    await store.send(.filesReceived([Self.ipa, Self.apk]))
    #expect(store.state.fresh == [uuid(0), uuid(1)])
    #expect(store.state.flashes == 1)
    @Shared(.notchIndicators) var indicators
    #expect(indicators[ShelfFeature.id] == NotchIndicator(leading: [.symbol("tray.full")], trailing: [.text("2")], flash: 1))
    await store.send(.tabHidden) { $0.fresh = [] }
    await store.send(.stop)
    #expect(indicators[ShelfFeature.id] == nil)
  }

  @Test
  func filesThatArriveBeforeLoadingWait() async {
    let store = makeStore()
    await store.send(.filesReceived([Self.ipa])) { $0.pending = [Self.ipa] }
    await store.send(.start)
    await store.receive(\.loaded)
    #expect(contents(store) == [.file(Self.ipa)])
    #expect(store.state.pending.isEmpty)
    await store.send(.stop)
  }

  @Test
  func imagesWithoutFilesAndVortexFilesAreKeptAsCopies() async {
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.image(Data([1, 2, 3]))]))
    await store.receive(\.copySaved)
    let image = store.state.items.first
    #expect(image?.fileURL?.lastPathComponent.hasPrefix("Image ") == true)
    #expect(written.value == [image?.fileURL])

    let clipboardImage = DataFolder.url.appending(path: "Clipboard/ABC/Image.png")
    await store.send(.dropped([.file(clipboardImage)]))
    await store.receive(\.copySaved)
    #expect(store.state.items.first?.content == .copy(fileName: "Image.png"))
    #expect(copied.value == [store.state.items.first?.fileURL])

    let folders = store.state.items.compactMap { $0.fileURL?.deletingLastPathComponent() }
    await store.send(.clearTapped)
    await store.send(.stop)
    await store.finish()
    #expect(Set(removed.value) == Set(folders))
  }

  // MARK: - Expiry

  @Test
  func unpinnedItemsLeaveAfterADay() async {
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.file(Self.ipa)]))
    await store.send(.dropped([.image(Data([1]))]))
    await store.receive(\.copySaved)
    await store.send(.dropped([.file(Self.notes)]))
    await store.send(.pinTapped(uuid(2)))

    now.withValue { $0 += ShelfFeature.lifetime - 1 }
    await clock.advance(by: .seconds(600))
    await store.receive(\.expiryCheckDue)
    #expect(store.state.items.count == 3)
    now.withValue { $0 += 2 }
    await clock.advance(by: .seconds(600))
    await store.receive(\.expiryCheckDue)
    #expect(contents(store) == [.file(Self.notes)])
    await store.send(.stop)
    await store.finish()
    #expect(removed.value.count == 1)
  }

  @Test
  func expiredItemsLeaveAtLaunch() async throws {
    let old = ShelfItem(id: uuid(9), content: .file(Self.ipa), addedAt: now.value.addingTimeInterval(-ShelfFeature.lifetime - 1))
    try ShelfItem.migrator.migrate(database)
    try await database.write { db in try ShelfItem.save([old], in: db) }
    let store = makeStore()
    await start(store)
    #expect(store.state.items.isEmpty)
    await store.send(.stop)
  }

  // MARK: - Selection and actions

  @Test
  func clicksSelectLikeFinder() async {
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.file(Self.ipa), .file(Self.apk), .file(Self.notes)]))
    await store.send(.itemClicked(uuid(0), DragSourceClick(count: 1, modifiers: []))) { $0.selection = [uuid(0)] }
    await store.send(.itemClicked(uuid(2), DragSourceClick(count: 1, modifiers: .shift))) {
      $0.selection = [uuid(0), uuid(1), uuid(2)]
    }
    await store.send(.itemClicked(uuid(1), DragSourceClick(count: 1, modifiers: .command))) {
      $0.selection = [uuid(0), uuid(2)]
    }
    #expect(store.state.dragItems(startingAt: uuid(2)) == [.file(Self.ipa), .file(Self.notes)])
    #expect(store.state.dragItems(startingAt: uuid(1)) == [.file(Self.apk)])
    await store.send(.backgroundClicked) { $0.selection = [] }
    await store.send(.stop)
  }

  @Test
  func spaceShowsTheSelectionInQuickLook() async {
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.file(Self.ipa), .text("not a file"), .file(Self.apk)]))
    await store.send(.selectAllPressed)
    await store.send(.quickLookPressed)
    await store.send(.stop)
    await store.finish()
    #expect(quickLooked.value == [[Self.ipa, Self.apk]])
  }

  @Test
  func doubleClickOpensTheFile() async {
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.file(Self.ipa)]))
    await store.send(.itemClicked(uuid(0), DragSourceClick(count: 2, modifiers: [])))
    await store.send(.stop)
    await store.finish()
    #expect(opened.value == [Self.ipa])
  }

  @Test
  func missingFilesCantBeDragged() async {
    missing.setValue([Self.apk])
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.file(Self.ipa), .file(Self.apk)]))
    await store.receive(\.infoLoaded)
    #expect(store.state.unavailable == [uuid(1)])
    await store.send(.selectAllPressed)
    #expect(store.state.dragItems(startingAt: uuid(0)) == [.file(Self.ipa)])
    await store.send(.stop)
  }

  @Test
  func removingTakesTheSelectionOffAndClearKeepsPinned() async {
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.file(Self.ipa), .file(Self.apk), .file(Self.notes)]))
    await store.send(.pinTapped(uuid(2)))
    await store.send(.itemClicked(uuid(0), DragSourceClick(count: 1, modifiers: [])))
    await store.send(.removeSelectedPressed)
    #expect(contents(store) == [.file(Self.apk), .file(Self.notes)])
    await store.send(.clearTapped)
    #expect(contents(store) == [.file(Self.notes)])
    await store.send(.stop)
    await store.finish()
    #expect(removed.value.isEmpty)
  }

  // MARK: - Saving

  @Test
  func shelfSurvivesARelaunchInOrder() async {
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.file(Self.ipa), .file(Self.apk)]))
    await store.send(.dropped([.file(Self.notes)]))
    await store.send(.pinTapped(uuid(1)))
    await store.send(.stop)
    await store.finish()

    let relaunched = makeStore()
    await start(relaunched)
    #expect(contents(relaunched) == [.file(Self.notes), .file(Self.ipa), .file(Self.apk)])
    #expect(relaunched.state.items[id: uuid(1)]?.isPinned == true)
    await relaunched.send(.stop)
  }
}
