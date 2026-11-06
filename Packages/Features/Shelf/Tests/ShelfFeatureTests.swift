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
      $0.fileClient.contents = { _ in [] }
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
    #expect(indicators[ShelfFeature.id] == NotchIndicator(
      leading: [.symbol("tray.full")], trailing: [.text("2")], flash: 1, flashColor: ShelfSettings.defaultFlashColors[1]
    ))
    // Once the shelf counts as seen, the files stay on it but leave the notch, without another flash.
    await store.send(.tabHidden) { $0.fresh = [] }
    #expect(contents(store) == [.file(Self.ipa), .file(Self.apk)])
    #expect(indicators[ShelfFeature.id] == NotchIndicator(
      leading: [], trailing: [], flash: 1, flashColor: ShelfSettings.defaultFlashColors[1]
    ))
    await store.send(.stop)
    #expect(indicators[ShelfFeature.id] == nil)
  }

  @Test
  func whatTheUserPutsOnTheShelfStaysOutOfTheNotch() async {
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.file(Self.ipa), .image(Data([1]), fileExtension: "png")]))
    await store.receive(\.copySaved)
    #expect(store.state.items.count == 2)
    @Shared(.notchIndicators) var indicators
    #expect(indicators[ShelfFeature.id] == NotchIndicator(leading: [], trailing: [], flash: 0))
    #expect(NotchEars(indicators: indicators).isEmpty)
    await store.send(.stop)
    await store.finish()
  }

  @Test
  func theNotchCountsOnlyFilesThatCameByThemselves() async {
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.file(Self.notes)]))
    await store.send(.filesReceived([Self.ipa, Self.apk]))
    @Shared(.notchIndicators) var indicators
    #expect(indicators[ShelfFeature.id] == NotchIndicator(
      leading: [.symbol("tray.full")], trailing: [.text("2")], flash: 1, flashColor: ShelfSettings.defaultFlashColors[1]
    ))
    // Taking one of them off lowers the number; the user's own file leaving changes nothing.
    await store.send(.removeTapped(uuid(1)))
    #expect(indicators[ShelfFeature.id]?.trailing == [.text("1")])
    await store.send(.removeTapped(uuid(0)))
    #expect(indicators[ShelfFeature.id]?.trailing == [.text("1")])
    await store.send(.clearTapped)
    #expect(NotchEars(indicators: indicators).isEmpty)
    await store.send(.stop)
  }

  @Test
  func aNewFileThatExpiresLeavesTheNotch() async {
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.file(Self.notes)]))
    await store.send(.pinTapped(uuid(0)))
    await store.send(.filesReceived([Self.ipa]))
    now.withValue { $0 += ShelfFeature.lifetime + 1 }
    await clock.advance(by: .seconds(600))
    await store.receive(\.expiryCheckDue)
    #expect(contents(store) == [.file(Self.notes)])
    @Shared(.notchIndicators) var indicators
    #expect(NotchEars(indicators: indicators).isEmpty)
    await store.send(.stop)
    await store.finish()
  }

  @Test
  func theFlashColorFollowsTheNumberOfNewFiles() async {
    let store = makeStore()
    await start(store)
    let (blue, green) = (ShelfSettings.defaultFlashColors[0], ShelfSettings.defaultFlashColors[1])
    await store.send(.filesReceived([Self.ipa])) { _ in }
    #expect(store.state.flashColor == blue)
    await store.send(.filesReceived([Self.apk]))
    #expect(store.state.flashColor == green)
    await store.send(.filesReceived([Self.notes]))
    #expect(store.state.flashColor == .white)
    #expect(store.state.flashes == 3)
    // Looking at the shelf starts the count over.
    await store.send(.tabHidden)
    await store.send(.filesReceived([URL(fileURLWithPath: "/Users/me/Builds/next.ipa")]))
    #expect(store.state.flashColor == blue)
    await store.send(.stop)
  }

  @Test
  func anEmptyShelfShowsNoEarsButCanFlash() async {
    let store = makeStore()
    await start(store)
    @Shared(.notchIndicators) var indicators
    #expect(indicators[ShelfFeature.id] == NotchIndicator(leading: [], trailing: [], flash: 0))
    #expect(NotchEars(indicators: indicators).isEmpty)
    await store.send(.stop)
  }

  @Test
  func theTestPlaysEveryColorThenWhiteThreeSecondsLater() async {
    let store = makeStore()
    await start(store)
    let (blue, green) = (ShelfSettings.defaultFlashColors[0], ShelfSettings.defaultFlashColors[1])
    await store.send(.testFlashTapped)
    await clock.advance(by: .milliseconds(2900))
    #expect(store.state.flashes == 0)
    await clock.advance(by: .milliseconds(100))
    await store.receive(\.testFlash) {
      $0.flashColor = blue
      $0.flashes = 1
    }
    await clock.advance(by: .seconds(1.8))
    await store.receive(\.testFlash) {
      $0.flashColor = green
      $0.flashes = 2
    }
    await clock.advance(by: .seconds(1.8))
    await store.receive(\.testFlash) {
      $0.flashColor = .white
      $0.flashes = 3
    }
    await clock.advance(by: .seconds(1.8))
    await store.send(.stop)
    await store.finish()
  }

  @Test
  func flashColorsCanBeAddedChangedRemovedAndReset() async {
    let store = makeStore()
    let red = ColorValue(hex: 0xFF5A5A)
    await store.send(.flashColorAdded)
    #expect(store.state.settings.flashColors == ShelfSettings.defaultFlashColors + [ShelfSettings.moreFlashColors[0]])
    await store.send(.flashColorChanged(index: 0, red))
    #expect(store.state.settings.flashColors.first == red)
    #expect(store.state.settings.flashColor(forNewFiles: 3) == ShelfSettings.moreFlashColors[0])
    #expect(store.state.settings.flashColor(forNewFiles: 4) == .white)
    for _ in 0..<3 { await store.send(.lastFlashColorRemoved) }
    #expect(store.state.settings.flashColors.isEmpty)
    #expect(store.state.settings.flashColor(forNewFiles: 1) == .white)
    await store.send(.flashColorsReset)
    #expect(store.state.settings.flashColors == ShelfSettings.defaultFlashColors)
  }

  @Test
  func dropsBeforeLoadingWaitAndKeepTheSavedShelf() async throws {
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.file(Self.ipa), .file(Self.apk)]))
    await store.send(.stop)
    await store.finish()

    let relaunched = makeStore()
    relaunched.dependencies.uuid = UUIDGenerator { UUID() }
    await relaunched.send(.dropped([.file(Self.notes)]))
    await relaunched.send(.removeSelectedPressed)
    await relaunched.send(.start)
    await relaunched.receive(\.loaded)
    #expect(contents(relaunched) == [.file(Self.notes), .file(Self.ipa), .file(Self.apk)])
    await relaunched.send(.stop)
    await relaunched.finish()
    #expect(try await database.read(ShelfItem.fetchAllReadable).map(\.content) == contents(relaunched))
  }

  @Test
  func filesThatArriveBeforeLoadingWait() async {
    let store = makeStore()
    await store.send(.filesReceived([Self.ipa])) {
      $0.pending = [ShelfFeature.State.Arrival(items: [.file(Self.ipa)], isFresh: true)]
    }
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
    await store.send(.dropped([.image(Data([1, 2, 3]), fileExtension: "jpeg")]))
    await store.receive(\.copySaved)
    let image = store.state.items.first
    #expect(image?.fileURL?.lastPathComponent.hasPrefix("Image ") == true)
    #expect(image?.fileURL?.pathExtension == "jpeg")
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

  @Test
  func aTemporaryFileIsKeptAsACopyUnderItsName() async {
    let store = makeStore()
    await start(store)
    // A screenshot dragged from its floating thumbnail: macOS deletes the file once the drag is over.
    let screenshot = URL(
      fileURLWithPath: "/var/folders/ab/cd/T/TemporaryItems/NSIRD_screencaptureui_1/Screenshot 2026-10-07 at 12.39.05.png"
    )
    await store.send(.dropped([.file(screenshot)]))
    await store.receive(\.copySaved)
    #expect(store.state.items.first?.content == .copy(fileName: "Screenshot 2026-10-07 at 12.39.05.png"))
    #expect(copied.value == [store.state.items.first?.fileURL])
    await store.send(.stop)
    await store.finish()
  }

  /// An image dropped without a file is named in macOS's words, from the catalog; its date and time read the same in
  /// every language.
  @Test
  func anImageWithoutAFileIsNamedByItsDateAndTime() throws {
    let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 14, minute: 3, second: 12)))
    #expect(ShelfFeature.imageFileName(addedAt: date, fileExtension: "jpeg") == "Image 2026-10-04 at 14.03.12.jpeg")
  }

  @Test
  func aFileOfVortexsOwnDroppedAgainMovesItsCopyToTheFront() async {
    let store = makeStore()
    await start(store)
    let clipboardImage = DataFolder.url.appending(path: "Clipboard/ABC/Image 2026-10-06 at 14.03.12.png")
    await store.send(.dropped([.file(clipboardImage)]))
    await store.receive(\.copySaved)
    now.withValue { $0 += 60 }
    await store.send(.dropped([.file(Self.ipa)]))
    now.withValue { $0 += 60 }
    // The same clipboard row dragged to the shelf again, here twice in one drop.
    await store.send(.dropped([.file(clipboardImage), .file(clipboardImage)]))
    #expect(contents(store) == [.copy(fileName: "Image 2026-10-06 at 14.03.12.png"), .file(Self.ipa)])
    #expect(store.state.items.first?.addedAt == now.value)
    #expect(copied.value.count == 1)
    await store.send(.stop)
    await store.finish()
  }

  // MARK: - Expiry

  @Test
  func unpinnedItemsLeaveAfterADay() async {
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.file(Self.ipa)]))
    await store.send(.dropped([.image(Data([1]), fileExtension: "png")]))
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

  // MARK: - Watched folder

  @Test
  func theWatchedFolderAddsFilesOnceTheyAreFullyWritten() async {
    let changes = AsyncStream.makeStream(of: URL.self)
    let sizes = LockIsolated<[URL: Int64]>([:])
    let builds = URL(fileURLWithPath: "/Users/me/Builds")
    let store = makeStore()
    store.dependencies.fileClient.changes = { [changes] _ in changes.stream }
    store.dependencies.fileClient.info = { [sizes] url in sizes.value[url].map { FileInfo(size: $0, isDirectory: false) } }
    store.dependencies.fileClient.chooseFolder = { builds }

    await store.send(.chooseFolderTapped)
    await store.receive(\.folderChosen)
    #expect(store.state.settings.watchedFolders == [
      ShelfSettings.WatchedFolder(folder: builds, extensions: ShelfSettings.defaultExtensions),
    ])
    await start(store)

    sizes.setValue([Self.ipa: 10, Self.notes: 5])
    changes.continuation.yield(Self.notes)
    changes.continuation.yield(Self.ipa)
    await store.receive(\.watchedFileChanged)
    await store.receive(\.watchedFileChanged)
    #expect(store.state.waitingFiles == [Self.ipa])
    await clock.advance(by: ShelfFeature.settleInterval)
    sizes.setValue([Self.ipa: 20, Self.notes: 5])
    await clock.advance(by: ShelfFeature.settleInterval)
    await clock.advance(by: ShelfFeature.settleInterval)
    #expect(store.state.items.isEmpty)
    await clock.advance(by: ShelfFeature.settleInterval)
    await store.receive(\.watchedFileWritten)
    #expect(contents(store) == [.file(Self.ipa)])
    #expect(store.state.fresh == [uuid(0)])
    #expect(store.state.flashes == 1)
    #expect(store.state.waitingFiles.isEmpty)
    await store.send(.stop)
  }

  @Test
  func aChangeStartsTheWaitOverAndVanishedOrEmptyFilesAreSkipped() async {
    let changes = AsyncStream.makeStream(of: URL.self)
    let empty = URL(fileURLWithPath: "/Users/me/Builds/placeholder.zip")
    let sizes = LockIsolated<[URL: Int64]>([Self.apk: 7, empty: 0])
    let store = makeStore()
    store.dependencies.fileClient.changes = { [changes] _ in changes.stream }
    store.dependencies.fileClient.info = { [sizes] url in sizes.value[url].map { FileInfo(size: $0, isDirectory: false) } }
    await store.send(.folderChosen(URL(fileURLWithPath: "/Users/me/Builds")))
    await start(store)

    let temporary = URL(fileURLWithPath: "/Users/me/Builds/app.apk.tmp.apk")
    for url in [temporary, empty, Self.apk] {
      changes.continuation.yield(url)
      await store.receive(\.watchedFileChanged)
    }
    await clock.advance(by: ShelfFeature.settleInterval)
    await store.receive(\.watchedFileGone)
    changes.continuation.yield(Self.apk)
    await store.receive(\.watchedFileChanged)
    await clock.advance(by: ShelfFeature.settleInterval)
    await store.receive(\.watchedFileGone)
    await clock.advance(by: ShelfFeature.settleInterval)
    #expect(store.state.items.isEmpty)
    await clock.advance(by: ShelfFeature.settleInterval)
    await store.receive(\.watchedFileWritten)
    #expect(contents(store) == [.file(Self.apk)])
    #expect(store.state.waitingFiles.isEmpty)
    await store.send(.stop)
  }

  @Test
  func stoppingCancelsTheWaits() async {
    let changes = AsyncStream.makeStream(of: URL.self)
    let store = makeStore()
    store.dependencies.fileClient.changes = { [changes] _ in changes.stream }
    store.dependencies.fileClient.info = { _ in FileInfo(size: 7, isDirectory: false) }
    await store.send(.folderChosen(URL(fileURLWithPath: "/Users/me/Builds")))
    await start(store)
    changes.continuation.yield(Self.apk)
    await store.receive(\.watchedFileChanged)
    await store.send(.stop) { $0.waitingFiles = [] }
    await clock.advance(by: .seconds(10))
    await store.finish()
    #expect(store.state.items.isEmpty)
  }

  @Test
  func fileTypesAreCleanedUp() async {
    let builds = URL(fileURLWithPath: "/b")
    let store = makeStore()
    await store.send(.folderChosen(builds))
    await store.send(.extensionsChanged(builds, " ipa, .APK  *.dmg,,ipa "))
    #expect(store.state.settings.watchedFolders.first?.extensions == ["ipa", "apk", "dmg"])
    #expect(store.state.settings.takes(URL(fileURLWithPath: "/b/App.IPA")))
    #expect(store.state.settings.takes(URL(fileURLWithPath: "/b/sub/App.ipa")))
    #expect(!store.state.settings.takes(URL(fileURLWithPath: "/b/notes.txt")))
    #expect(!store.state.settings.takes(URL(fileURLWithPath: "/b/.App.ipa")))
    #expect(!store.state.settings.takes(URL(fileURLWithPath: "/elsewhere/App.ipa")))
    await store.send(.extensionsChanged(builds, ""))
    #expect(store.state.settings.takes(URL(fileURLWithPath: "/b/notes.txt")))
  }

  @Test
  func aPathToWatchCanBeAFolderAnExampleFileOrAPattern() async {
    let builds = URL(fileURLWithPath: "/Users/me/StudioProjects/app/last_builds")
    let example = builds.appending(path: "kurzurlaub-dev-1.0.0-65-20260923-230220.aab")
    let store = makeStore()
    store.dependencies.fileClient.info = { url in
      switch url.path {
      case builds.path, "/Users/me/Exports": FileInfo(size: nil, isDirectory: true)
      case example.path: FileInfo(size: 1, isDirectory: false)
      default: nil
      }
    }
    await store.send(.watchPathSubmitted(example.path))
    await store.receive(\.watchPathChecked)
    #expect(store.state.settings.watchedFolders == [ShelfSettings.WatchedFolder(folder: builds, extensions: ["aab"])])

    // The same folder again with a pattern adds the type.
    await store.send(.watchPathSubmitted(builds.path + "/*.apk"))
    await store.receive(\.watchPathChecked)
    #expect(store.state.settings.watchedFolders == [ShelfSettings.WatchedFolder(folder: builds, extensions: ["aab", "apk"])])

    await store.send(.watchPathSubmitted(" /Users/me/Exports/ "))
    await store.receive(\.watchPathChecked)
    #expect(store.state.settings.watchedFolders.last
      == ShelfSettings.WatchedFolder(folder: URL(fileURLWithPath: "/Users/me/Exports"), extensions: ShelfSettings.defaultExtensions))

    await store.send(.watchPathSubmitted("/Users/me/Missing/*.ipa"))
    await store.receive(\.watchPathChecked) { $0.pathNotFound = "/Users/me/Missing/*.ipa" }
    #expect(store.state.settings.watchedFolders.count == 2)

    await store.send(.stopWatchingTapped(builds))
    #expect(store.state.settings.watchedFolders.map(\.folder) == [URL(fileURLWithPath: "/Users/me/Exports")])
  }

  @Test
  func everyWatchedFolderIsWatched() async {
    let watched = LockIsolated<[String]>([])
    let store = makeStore()
    store.dependencies.fileClient.changes = { [watched] folder in
      watched.withValue { $0.append(folder.lastPathComponent) }
      return AsyncStream { _ in }
    }
    await store.send(.folderChosen(URL(fileURLWithPath: "/a/ios")))
    await store.send(.folderChosen(URL(fileURLWithPath: "/a/android")))
    await start(store)
    await store.send(.stop)
    await store.finish()
    #expect(Set(watched.value) == ["ios", "android"])
  }

  @Test
  func rowsOfANewerVersionSurviveAndOrderIsKept() async throws {
    try ShelfItem.migrator.migrate(database)
    try await database.write { db in
      try db.execute(sql: """
        INSERT INTO shelf_item (id, content, addedAt, isPinned, position)
        VALUES ('FUTURE', '{"future":{}}', '2026-10-04 10:00:00.000', 1, 0)
        """)
    }
    let store = makeStore()
    await start(store)
    await store.send(.dropped([.file(Self.ipa)]))
    await store.send(.dropped([.file(Self.apk)]))
    await store.send(.removeTapped(uuid(0)))
    await store.send(.stop)
    await store.finish()
    #expect(try await database.read { try String.fetchSet($0, sql: "SELECT id FROM shelf_item") } == [
      "FUTURE", uuid(1).uuidString,
    ])
  }

  @Test
  func anUnreadableShelfIsLeftAloneAndDropsStillWork() async throws {
    try await database.write { db in
      try db.execute(sql: "CREATE TABLE shelf_item (id TEXT PRIMARY KEY)")
    }
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loadFailed)
    await store.receive(\.loaded)
    await store.send(.dropped([.file(Self.ipa)]))
    #expect(contents(store) == [.file(Self.ipa)])
    #expect(!store.state.savesToDisk)
    await store.send(.stop)
  }

  @Test
  func copiesWithoutARowAreRemovedAtStart() async throws {
    try ShelfItem.migrator.migrate(database)
    try await database.write { db in
      try db.execute(sql: """
        INSERT INTO shelf_item (id, content, addedAt, isPinned, position)
        VALUES ('KEPT', '{"future":{}}', '2026-10-04 10:00:00.000', 1, 0)
        """)
    }
    let orphan = ShelfItem.copiesFolder.appending(path: "ORPHAN")
    let store = makeStore()
    store.dependencies.fileClient.contents = { _ in [ShelfItem.copiesFolder.appending(path: "KEPT"), orphan] }
    await start(store)
    await store.send(.stop)
    await store.finish()
    #expect(removed.value == [orphan])
  }

  @Test
  func aDatabaseOnlyInMemoryRemovesNoCopy() async {
    // Its file didn't open: the copies are then all that is left.
    let store = makeStore()
    store.dependencies.databaseIsOnDisk = false
    store.dependencies.fileClient.contents = { _ in [ShelfItem.copiesFolder.appending(path: "UNREAD")] }
    await start(store)
    await store.send(.stop)
    await store.finish()
    #expect(removed.value.isEmpty)
  }
}
