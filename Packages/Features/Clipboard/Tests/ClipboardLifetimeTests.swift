import ComposableArchitecture
import Foundation
import GRDB
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureClipboard

/// Keep history: items go by age, past 10,000 or 1 GB; Clear and a shorter time can be taken back for 5 s.
extension ClipboardFeatureTests {
  nonisolated static let day: TimeInterval = 86_400

  func history(_ items: [ClipboardItem]) -> IdentifiedArrayOf<ClipboardItem> {
    IdentifiedArray(uniqueElements: items.sorted(by: ClipboardFeature.displayOrder))
  }

  func image(id: Int, copiedAt: Date, bytes: Int) -> ClipboardItem {
    ClipboardItem(
      id: uuid(id), content: .image(fileName: "Image.png"), source: Self.terminal, copiedAt: copiedAt,
      fingerprint: "image:\(id)", byteSize: bytes
    )
  }

  // MARK: - What goes

  @Test
  func itemsGoOnceTheyAreOlderThanTheLifetimeExceptPinnedOnes() {
    let now = now.value
    let items = history([
      item("today", id: 0, copiedAt: now - Self.day / 2),
      item("last week", id: 1, copiedAt: now - 6 * Self.day),
      item("two weeks ago", id: 2, copiedAt: now - 14 * Self.day),
      item("last year", id: 3, copiedAt: now - 300 * Self.day),
      item("pinned long ago", id: 4, copiedAt: now - 1_000 * Self.day, isPinned: true),
      item("two years ago", id: 5, copiedAt: now - 730 * Self.day),
    ])
    func removed(_ lifetime: HistoryLifetime) -> Set<UUID> {
      Set(ClipboardFeature.removals(items, lifetime: lifetime, now: now))
    }
    #expect(removed(.week) == [uuid(2), uuid(3), uuid(5)])
    #expect(removed(.month) == [uuid(3), uuid(5)])
    #expect(removed(.threeMonths) == [uuid(3), uuid(5)])
    #expect(removed(.year) == [uuid(5)])
    #expect(removed(.forever).isEmpty)
  }

  @Test
  func pastTenThousandUnpinnedItemsTheOldestGo() {
    let now = now.value
    var items = (0..<10_002).map { item("item \($0)", id: $0, copiedAt: now - Double($0)) }
    // Pinned ones don't count.
    items += (0..<5).map { item("pinned \($0)", id: 20_000 + $0, copiedAt: now - 1_000_000, isPinned: true) }
    #expect(ClipboardFeature.removals(history(items), lifetime: .forever, now: now) == [uuid(10_000), uuid(10_001)])
  }

  @Test
  func pastOneGigabyteTheOldestImagesGoFirstThenTheOldestOfAnyKind() {
    let now = now.value
    let megabyte = 1_000_000
    var bigText = item("big", id: 9, copiedAt: now - 9)
    bigText.byteSize = 300 * megabyte
    var secret = item("secret", id: 7, copiedAt: now - 10)
    secret.isConcealed = true
    secret.byteSize = 900 * megabyte
    var pinned = image(id: 8, copiedAt: now - 20, bytes: 2_000 * megabyte)
    pinned.isPinned = true
    let items = history([
      image(id: 1, copiedAt: now - 1, bytes: 400 * megabyte),
      bigText,
      image(id: 2, copiedAt: now - 2, bytes: 200 * megabyte),
      image(id: 3, copiedAt: now - 3, bytes: 200 * megabyte),
      secret,
      pinned,
    ])
    // 1,100 MB unpinned (a secret takes nothing, a pinned item doesn't count): the oldest image is enough.
    #expect(ClipboardFeature.removals(items, lifetime: .forever, now: now) == [uuid(3)])

    // With no image left, the oldest of any kind; an item that takes nothing stays.
    var texts = (0..<3).map { index in
      var text = item("text \(index)", id: 30 + index, copiedAt: now - Double(index))
      text.byteSize = 400 * megabyte
      return text
    }
    texts.append(secret)
    #expect(ClipboardFeature.removals(history(texts), lifetime: .forever, now: now) == [uuid(32)])
  }

  @Test
  func theHistoryRowCountsEveryItemAndASecretTakesNothing() {
    var state = ClipboardFeature.State()
    var secret = item("hunter2", id: 1, copiedAt: now.value)
    secret.isConcealed = true
    state.items = history([
      item("text", id: 0, copiedAt: now.value),
      secret,
      image(id: 2, copiedAt: now.value - 5, bytes: 1_000),
    ])
    state.items[id: uuid(2)]?.isPinned = true
    #expect(state.historySize.items == 3)
    #expect(state.historySize.bytes == 4 + 1_000)
  }

  // MARK: - When

  @Test
  func itemsPastTheLifetimeGoAtLaunchWithTheirRowsAndImages() async throws {
    let old = image(id: 1, copiedAt: now.value - 31 * Self.day, bytes: 10)
    try saveRows([item("new", id: 0, copiedAt: now.value), old])
    let store = makeStore()
    store.exhaustivity = .off
    await store.send(.start)
    await store.receive(\.loaded)
    #expect(store.state.items.map(\.content) == [.text("new")])
    await store.receive(\.written)
    #expect(try savedHistory().map(\.content) == [.text("new")])
    #expect(removedFiles.value == [old.imageURL!.deletingLastPathComponent()])
    await store.send(.stop)
  }

  @Test
  func itemsPastTheLifetimeGoEveryHourWhileTheFeatureIsOn() async throws {
    try saveRows([item("old", id: 0, copiedAt: now.value - 29 * Self.day), item("new", id: 1, copiedAt: now.value)])
    let store = makeStore()
    store.exhaustivity = .off
    await store.send(.start)
    await store.receive(\.loaded)
    #expect(store.state.items.count == 2)
    // Two days later, an hour after the last check.
    now.withValue { $0 += 2 * Self.day }
    await clock.advance(by: ClipboardFeature.checkInterval)
    await store.receive(\.hourPassed)
    #expect(store.state.items.map(\.content) == [.text("new")])
    await store.receive(\.written)
    #expect(try savedHistory().map(\.content) == [.text("new")])
    // Stopped, nothing more is checked: "new" grows old, and still nothing removes it.
    await store.send(.stop)
    now.withValue { $0 += 40 * Self.day }
    await clock.advance(by: ClipboardFeature.checkInterval * 3)
    await store.finish()
    // Whatever arrived since is applied to the state the store shows.
    await store.skipReceivedActions(strict: false)
    #expect(store.state.items.map(\.content) == [.text("new")])
    #expect(try savedHistory().map(\.content) == [.text("new")])
  }

  @Test
  func itemsPastTheLifetimeGoAfterACopyAndWhenTheTabShows() async throws {
    try saveRows([item("old", id: 100, copiedAt: now.value - 29 * Self.day)])
    let store = makeStore()
    store.exhaustivity = .off
    await store.send(.start)
    await store.receive(\.loaded)
    now.withValue { $0 += 2 * Self.day }
    await store.send(.tabShown)
    #expect(store.state.items.isEmpty)

    copy(.text("a"))
    await store.receive(\.copied)
    now.withValue { $0 += 31 * Self.day }
    copy(.text("b"))
    await store.receive(\.copied)
    #expect(store.state.items.map(\.content) == [.text("b")])
    await store.send(.stop)
  }

  // MARK: - A shorter time, Clear, Undo

  /// A history aged 1, 10 and 40 days, kept for a year (or `lifetime`, which may remove some at launch).
  func agedStore(_ lifetime: HistoryLifetime = .year) async throws -> TestStoreOf<ClipboardFeature> {
    // Ids the store's own never reach.
    let images = [image(id: 102, copiedAt: now.value - 40 * Self.day, bytes: 10)]
    try saveRows([item("1 day", id: 100, copiedAt: now.value - Self.day), item("10 days", id: 101, copiedAt: now.value - 10 * Self.day)] + images)
    let store = makeStore()
    store.exhaustivity = .off
    store.state.$settings.withLock { $0.historyLifetime = lifetime }
    await store.send(.start)
    await store.receive(\.loaded)
    return store
  }

  @Test
  func aShorterTimeRemovesOlderItemsAndUndoBringsThemAndTheChoiceBack() async throws {
    let store = try await agedStore()
    let before = store.state.items
    await store.send(.lifetimeChanged(.week))
    #expect(store.state.settings.historyLifetime == .week)
    #expect(store.state.items.map(\.content) == [.text("1 day")])
    #expect(store.state.pendingRemoval?.reason == .lifetime(previous: .year))
    // Their rows stay while Undo can bring them back.
    #expect(try rowCount() == 3)

    await store.send(.undoTapped)
    #expect(store.state.items == before)
    #expect(store.state.settings.historyLifetime == .year)
    #expect(store.state.pendingRemoval == nil)
    await clock.advance(by: ClipboardFeature.undoTime)
    await store.send(.stop)
    await store.finish()
    #expect(try rowCount() == 3)
    #expect(removedFiles.value.isEmpty)
  }

  @Test
  func aShorterTimeIsFinalAfterFiveSecondsRowsAndImagesGo() async throws {
    let store = try await agedStore()
    let image = try #require(store.state.items.last?.imageURL)
    await store.send(.lifetimeChanged(.week))
    await clock.advance(by: ClipboardFeature.undoTime)
    await store.receive(\.undoExpired)
    #expect(store.state.pendingRemoval == nil)
    await store.send(.stop)
    await store.finish()
    #expect(try savedHistory().map(\.content) == [.text("1 day")])
    #expect(removedFiles.value == [image.deletingLastPathComponent()])
    #expect(store.state.settings.historyLifetime == .week)
  }

  @Test
  func aTimeThatRemovesNothingShowsNoUndo() async throws {
    let store = try await agedStore()
    await store.send(.lifetimeChanged(.threeMonths))
    #expect(store.state.items.count == 3)
    #expect(store.state.pendingRemoval == nil)
    await store.send(.lifetimeChanged(.forever))
    #expect(store.state.pendingRemoval == nil)
    await store.send(.stop)
  }

  @Test
  func choosingThePreviousTimeAgainWithinTheFiveSecondsWorksAsUndo() async throws {
    let store = try await agedStore(.month)
    #expect(store.state.items.map(\.content) == [.text("1 day"), .text("10 days")])
    await store.send(.lifetimeChanged(.week))
    #expect(store.state.items.map(\.content) == [.text("1 day")])
    await store.send(.lifetimeChanged(.month))
    #expect(store.state.settings.historyLifetime == .month)
    #expect(store.state.items.map(\.content) == [.text("1 day"), .text("10 days")])
    #expect(store.state.pendingRemoval == nil)
    await clock.advance(by: ClipboardFeature.undoTime)
    await store.send(.stop)
    await store.finish()
    #expect(try savedHistory().map(\.content) == [.text("1 day"), .text("10 days")])
  }

  @Test
  func anotherTimeWithinTheFiveSecondsUndoesTheFirstAndItsUndoGoesBackToTheChoiceBefore() async throws {
    let store = try await agedStore()
    #expect(store.state.items.count == 3)
    await store.send(.lifetimeChanged(.month))
    #expect(store.state.items.count == 2)
    await store.send(.lifetimeChanged(.week))
    #expect(store.state.items.map(\.content) == [.text("1 day")])
    #expect(store.state.pendingRemoval?.reason == .lifetime(previous: .year))
    await store.send(.undoTapped)
    #expect(store.state.settings.historyLifetime == .year)
    #expect(store.state.items.count == 3)
    await store.send(.stop)
    await store.finish()
    #expect(try rowCount() == 3)
    #expect(removedFiles.value.isEmpty)
  }

  @Test
  func aTimeChosenWithinTheFiveSecondsOfAClearLetsTheClearStand() async throws {
    let store = try await agedStore()
    await store.send(.clearTapped)
    await store.send(.lifetimeChanged(.week))
    #expect(store.state.items.isEmpty)
    #expect(store.state.pendingRemoval == nil)
    await store.send(.undoTapped)
    #expect(store.state.items.isEmpty)
    #expect(store.state.settings.historyLifetime == .week)
    await store.send(.stop)
    await store.finish()
    #expect(try rowCount() == 0)
  }

  @Test
  func clearCanBeTakenBackThenIsFinalAfterFiveSeconds() async throws {
    let store = try await agedStore()
    await store.send(.pinTapped(uuid(101)))
    let before = store.state.items
    await store.send(.clearTapped)
    #expect(store.state.items.map(\.content) == [.text("10 days")])
    #expect(store.state.pendingRemoval?.reason == .cleared)
    await store.send(.undoTapped)
    #expect(store.state.items == before)

    await store.send(.clearTapped)
    // The window closes and opens again half-way: closing sends the reducer nothing, opening sends what the tab and
    // the settings section send (`.task(id: isWindowOpen)`). The removal still waits, and still ends at 5 s.
    await clock.advance(by: .seconds(2))
    await store.send(.tabShown)
    await store.send(.settingsShown)
    #expect(store.state.pendingRemoval?.reason == .cleared)
    #expect(try rowCount() == 3)
    await clock.advance(by: .seconds(2))
    #expect(store.state.pendingRemoval != nil)
    await clock.advance(by: .seconds(1))
    await store.receive(\.undoExpired)
    await store.send(.stop)
    await store.finish()
    #expect(try savedHistory().map(\.content) == [.text("10 days")])
    #expect(removedFiles.value.count == 1)
  }

  @Test
  func clearTwiceSettlesTheFirstAndUndoBringsBackTheSecond() async throws {
    let store = try await agedStore()
    await store.send(.clearTapped)
    copy(.text("copied after Clear"))
    await store.receive(\.copied)
    await store.send(.clearTapped)
    #expect(store.state.pendingRemoval?.items.map(\.content) == [.text("copied after Clear")])
    await store.send(.undoTapped)
    #expect(store.state.items.map(\.content) == [.text("copied after Clear")])
    await store.send(.stop)
    await store.finish()
    #expect(try savedHistory().map(\.content) == [.text("copied after Clear")])
  }

  @Test
  func anItemCopiedAgainDuringTheUndoTimeComesBackAsNewAndUndoBringsTheRest() async throws {
    let store = try await agedStore()
    await store.send(.clearTapped)
    copy(.text("10 days"))
    await store.receive(\.copied)
    // The same item, with its row, now the newest.
    let copiedAgain = try #require(store.state.items.first)
    #expect(copiedAgain.id == uuid(101))
    #expect(copiedAgain.copiedAt == now.value)
    await store.send(.undoTapped)
    #expect(store.state.items.map(\.content) == [.text("10 days"), .text("1 day"), .image(fileName: "Image.png")])
    #expect(store.state.items.first?.id == copiedAgain.id)
    await store.send(.stop)
    await store.finish()
    #expect(try savedHistory().map(\.id) == store.state.items.map(\.id))
  }

  @Test
  func readingTheHistoryAgainWithinTheUndoTimeShowsWhatIsOnDisk() async throws {
    let store = try await agedStore()
    await store.send(.clearTapped)
    // As QA's seed does: the rows of what Clear set aside are still there.
    let (items, _) = try await ClipboardFeature.loadHistory(database: database, files: store.dependencies.fileClient)
    await store.send(.loaded(items))
    #expect(store.state.items.count == 3)
    #expect(store.state.pendingRemoval == nil)
    await store.send(.undoTapped)
    await clock.advance(by: ClipboardFeature.undoTime)
    await store.send(.stop)
    await store.finish()
    #expect(try rowCount() == 3)
  }

  @Test
  func quittingWithinTheUndoTimeKeepsTheClearedItems() async throws {
    let store = try await agedStore()
    await store.send(.clearTapped)
    // Vortex quits: the five seconds never end.
    await store.send(.stop)

    let relaunched = makeStore()
    relaunched.exhaustivity = .off
    relaunched.state.$settings.withLock { $0.historyLifetime = .year }
    await relaunched.send(.start)
    await relaunched.receive(\.loaded)
    #expect(relaunched.state.items.count == 3)
    await relaunched.send(.stop)
  }

  /// What the next launch shows after Vortex quits now.
  func relaunched() async -> IdentifiedArrayOf<ClipboardItem> {
    let store = makeStore()
    store.exhaustivity = .off
    store.state.$settings.withLock { $0.historyLifetime = .year }
    await store.send(.start)
    await store.receive(\.loaded)
    await store.send(.stop)
    return store.state.items
  }

  @Test
  func aSecretCopiedWhileItsItemIsSetAsideTakesItsRowAtOnce() async throws {
    let store = try await agedStore()
    await store.send(.clearTapped)
    // Within the 5 s, the text cleared is copied from a password manager.
    copy(.text("10 days"), from: Self.passwords, concealed: true)
    await store.receive(\.copied)
    await store.receive(\.written)
    #expect(try savedTexts().contains("10 days") == false)
    // Undo never brings back a plain copy of the secret.
    await store.send(.undoTapped)
    #expect(store.state.items.filter { $0.content == .text("10 days") }.map(\.isConcealed) == [true])
    await store.send(.stop)
    await store.finish()
    #expect(await relaunched().contains { $0.content == .text("10 days") } == false)
  }

  @Test
  func anItemSetAsideAndCopiedAgainIsBackOnceEvenIfVortexQuits() async throws {
    let store = try await agedStore()
    await store.send(.clearTapped)
    copy(.text("10 days"))
    await store.receive(\.copied)
    await store.receive(\.written)
    #expect(store.state.items.map(\.content) == [.text("10 days")])
    // Vortex quits within the 5 s.
    await store.send(.stop)
    #expect(await relaunched().filter { $0.content == .text("10 days") }.count == 1)
  }

  // MARK: - Settings

  @Test
  func keepHistoryReadsAsAMonthWhenMissingOrUnknown() throws {
    func decoded(_ json: String) throws -> ClipboardSettings {
      try JSONDecoder().decode(ClipboardSettings.self, from: Data(json.utf8))
    }
    #expect(ClipboardSettings().historyLifetime == .month)
    #expect(try decoded("{}").historyLifetime == .month)
    #expect(try decoded(#"{"historyLifetime":"decade"}"#).historyLifetime == .month)
    #expect(try decoded(#"{"historyLifetime":"week","ignoredApps":[]}"#).historyLifetime == .week)
    // One broken key leaves the other.
    #expect(try decoded(#"{"historyLifetime":"forever","ignoredApps":7}"#).historyLifetime == .forever)
    #expect(HistoryLifetime.allCases.map(\.days) == [7, 30, 90, 365, nil])
  }
}
