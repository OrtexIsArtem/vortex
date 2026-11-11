import ComposableArchitecture
import Foundation
import GRDB
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureClipboard

/// Search in the tab: every word, any case, in texts, links, file names and app names; never a secret.
extension ClipboardFeatureTests {
  static let safari = AppInfo(bundleID: "com.apple.Safari", name: "Safari")
  static let preview = AppInfo(bundleID: "com.apple.Preview", name: "Preview")

  /// Runs a query as typed, past the pause, and returns what the tab shows.
  func search(_ query: String, _ store: TestStoreOf<ClipboardFeature>) async -> [ClipboardItem.Content] {
    await store.send(.queryChanged(query))
    await clock.advance(by: ClipboardFeature.searchDelay)
    await store.receive(\.searched)
    return store.state.shownItems.map(\.content)
  }

  /// A loaded history of a few kinds, every write in.
  func searchableStore() async throws -> TestStoreOf<ClipboardFeature> {
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    let copies: [(PasteboardContent, AppInfo)] = [
      (.text("Release notes for 0.1.3"), Self.terminal),
      (.text("Реліз 0.1.3 у ПОНЕДІЛОК"), Self.terminal),
      (.link(URL(string: "https://uk.wikipedia.org/wiki/%D0%9A%D0%B8%D1%97%D0%B2")!), Self.safari),
      (.files([URL(fileURLWithPath: "/tmp/Звіт за жовтень.pdf")]), Self.terminal),
      (.image(Data([0x89, 0x50])), Self.preview),
    ]
    for (content, source) in copies {
      copy(content, from: source)
      await store.receive(\.copied)
      if case .image = content { await store.receive(\.imageSaved) }
      await store.receive(\.written)
    }
    return store
  }

  @Test
  func searchFindsWhatHoldsEveryWordInAnyCase() async throws {
    let store = try await searchableStore()
    #expect(await search("NOTES release", store) == [.text("Release notes for 0.1.3")])
    #expect(await search("0.1.3", store) == [.text("Реліз 0.1.3 у ПОНЕДІЛОК"), .text("Release notes for 0.1.3")])
    // Ukrainian in any case.
    #expect(await search("понеділок РЕЛІЗ", store) == [.text("Реліз 0.1.3 у ПОНЕДІЛОК")])
    #expect(await search("notes понеділок", store).isEmpty)
    await store.send(.stop)
  }

  @Test
  func linksMatchDecodedFilesByNameAndAnyItemByItsApp() async throws {
    let store = try await searchableStore()
    #expect(await search("київ", store) == [.link(URL(string: "https://uk.wikipedia.org/wiki/%D0%9A%D0%B8%D1%97%D0%B2")!)])
    #expect(await search("звіт жовтень", store) == [.files([URL(fileURLWithPath: "/tmp/Звіт за жовтень.pdf")])])
    #expect(await search("safari", store).count == 1)
    // An image only by its app.
    #expect(await search("preview", store).first?.isImageForTest == true)
    #expect(await search("image", store).isEmpty)
    #expect(await search("png", store).isEmpty)
    await store.send(.stop)
  }

  @Test
  func secretsNeverMatchNotEvenByTheirApp() async throws {
    let store = try await searchableStore()
    copy(.text("hunter2 release"), from: Self.passwords, concealed: true)
    await store.receive(\.copied)
    #expect(await search("hunter2", store).isEmpty)
    #expect(await search("passwords", store).isEmpty)
    #expect(await search("release", store) == [.text("Release notes for 0.1.3")])

    // Found, then copied again from a password manager: it turns secret and leaves the results at once.
    copy(.text("Release notes for 0.1.3"), from: Self.passwords, concealed: true)
    await store.receive(\.copied)
    #expect(store.state.shownItems.isEmpty)
    await store.receive(\.written)
    await store.receive(\.searched)
    #expect(store.state.searchResults == [])
    await store.send(.stop)
  }

  @Test
  func resultsFollowCopiesPinsAndDeletes() async throws {
    let store = try await searchableStore()
    #expect(await search("0.1.3", store) == [.text("Реліз 0.1.3 у ПОНЕДІЛОК"), .text("Release notes for 0.1.3")])
    copy(.text("Hotfix 0.1.3"))
    await store.receive(\.copied)
    await store.receive(\.written)
    await store.receive(\.searched)
    #expect(store.state.shownItems.map(\.content) == [
      .text("Hotfix 0.1.3"), .text("Реліз 0.1.3 у ПОНЕДІЛОК"), .text("Release notes for 0.1.3"),
    ])
    // A found card works as any: pinned, it goes first; deleted, it goes.
    await store.send(.pinTapped(uuid(0)))
    await store.receive(\.written)
    await store.receive(\.searched)
    #expect(store.state.shownItems.first?.content == .text("Release notes for 0.1.3"))
    await store.send(.deleteTapped(uuid(1)))
    #expect(store.state.shownItems.map(\.content) == [.text("Release notes for 0.1.3"), .text("Hotfix 0.1.3")])
    await store.receive(\.written)
    await store.receive(\.searched)
    #expect(store.state.searchResults?.count == 2)
    await store.send(.stop)
  }

  @Test
  func typingWaitsForAPauseAndOnlyTheLastQueryRuns() async throws {
    try saveRows([item("release notes", id: 100, copiedAt: now.value), item("relay", id: 101, copiedAt: now.value - 60)])
    var state = ClipboardFeature.State()
    state.items = history([
      item("release notes", id: 100, copiedAt: now.value), item("relay", id: 101, copiedAt: now.value - 60),
    ])
    state.isLoaded = true
    let store = makeStore(state)
    await store.send(.queryChanged("re")) { $0.query = "re" }
    await clock.advance(by: .milliseconds(100))
    await store.send(.queryChanged("rele")) { $0.query = "rele" }
    await clock.advance(by: .milliseconds(100))
    await store.send(.queryChanged("relea")) { $0.query = "relea" }
    await clock.advance(by: ClipboardFeature.searchDelay)
    await store.receive(\.searched) { $0.searchResults = [uuid(100)] }
    // Emptied, the search is gone at once.
    await store.send(.queryChanged("  ")) {
      $0.query = "  "
      $0.searchResults = nil
    }
  }

  @Test
  func theSearchEmptiesWhenTheTabShows() async throws {
    let store = try await searchableStore()
    _ = await search("release", store)
    await store.send(.tabShown)
    #expect(store.state.query.isEmpty)
    #expect(store.state.searchResults == nil)
    #expect(store.state.shownItems.count == 5)
    await store.send(.stop)
  }

  @Test
  func aHistoryKeptInMemorySearchesMemory() async throws {
    try await database.write { db in
      try db.execute(sql: "CREATE TABLE clipboard_item (id TEXT PRIMARY KEY)")
    }
    let store = makeStore()
    store.exhaustivity = .off
    await store.send(.start)
    await store.receive(\.loadFailed)
    copy(.text("kept for this session"))
    await store.receive(\.copied)
    copy(.text("session password"), from: Self.passwords, concealed: true)
    await store.receive(\.copied)
    #expect(await search("SESSION", store) == [.text("kept for this session")])
    await store.send(.stop)
  }

  @Test
  func aHistoryKeptInMemoryUpdatesItsResultsOnCopiesPinsAndDeletes() async throws {
    try await database.write { db in
      try db.execute(sql: "CREATE TABLE clipboard_item (id TEXT PRIMARY KEY)")
    }
    let store = makeStore()
    store.exhaustivity = .off
    await store.send(.start)
    await store.receive(\.loadFailed)
    copy(.text("session one"))
    await store.receive(\.copied)
    #expect(await search("session", store) == [.text("session one")])
    copy(.text("session two"))
    await store.receive(\.copied)
    await store.receive(\.searched)
    #expect(store.state.shownItems.map(\.content) == [.text("session two"), .text("session one")])
    await store.send(.pinTapped(uuid(0)))
    await store.receive(\.searched)
    #expect(store.state.shownItems.map(\.content) == [.text("session one"), .text("session two")])
    await store.send(.deleteTapped(uuid(1)))
    await store.receive(\.searched)
    #expect(store.state.searchResults == [uuid(0)])
    await store.send(.stop)
  }

  // MARK: - Files on screen

  @Test
  func theNewestFileItemsAreCheckedWhenTheTabShowsTheOthersAsTheyComeOnScreen() async throws {
    let gone = URL(fileURLWithPath: "/tmp/gone.zip")
    missingFiles.setValue([gone])
    let checks = LockIsolated(0)
    let fileItems = (0..<130).map { index in
      ClipboardItem(
        id: uuid(100 + index), content: .files([index == 120 ? gone : URL(fileURLWithPath: "/tmp/\(index).zip")]),
        source: Self.terminal, copiedAt: now.value - Double(index), fingerprint: "files:\(index)", byteSize: 10
      )
    }
    var state = ClipboardFeature.State()
    state.items = history(fileItems)
    state.isLoaded = true
    let store = makeStore(state)
    store.exhaustivity = .off
    store.dependencies.fileClient.info = { [missingFiles] url in
      checks.withValue { $0 += 1 }
      return missingFiles.value.contains(url) ? nil : FileInfo(size: 1, isDirectory: false)
    }
    await store.send(.tabShown)
    await store.receive(\.filesChecked)
    #expect(checks.value == ClipboardFeature.filesCheckedOnShow)
    #expect(store.state.unavailable.isEmpty)

    await store.send(.cardAppeared(uuid(220)))
    await store.receive(\.filesChecked)
    #expect(store.state.unavailable == [uuid(220)])
    // Once per showing of the tab.
    await store.send(.cardAppeared(uuid(220)))
    await store.send(.cardAppeared(uuid(105)))
    #expect(checks.value == ClipboardFeature.filesCheckedOnShow + 1)
    // Shown again: checked again.
    await store.send(.tabShown)
    await store.receive(\.filesChecked)
    await store.send(.cardAppeared(uuid(220)))
    await store.receive(\.filesChecked)
    #expect(checks.value == 2 * ClipboardFeature.filesCheckedOnShow + 2)
    #expect(store.state.unavailable == [uuid(220)])
  }
}

extension ClipboardFeatureTests {
  @Test
  func undoGivesAFileItemItsNotFoundMarkBack() async throws {
    let gone = URL(fileURLWithPath: "/tmp/gone.zip")
    missingFiles.setValue([gone])
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.files([gone]))
    await store.receive(\.copied)
    await store.send(.tabShown)
    await store.receive(\.filesChecked)
    #expect(store.state.unavailable == [uuid(0)])
    await store.send(.clearTapped)
    await store.send(.undoTapped)
    #expect(store.state.unavailable == [uuid(0)])
    // Its card comes on screen again: it still can't be copied.
    await store.send(.cardAppeared(uuid(0)))
    await store.send(.itemTapped(uuid(0)))
    await store.send(.stop)
    await store.finish()
    #expect(written.value.isEmpty)
  }
}

extension ClipboardItem.Content {
  var isImageForTest: Bool {
    if case .image = self { true } else { false }
  }
}
