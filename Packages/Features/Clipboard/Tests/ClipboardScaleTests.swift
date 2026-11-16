import AppKit
import ComposableArchitecture
import Foundation
import GRDB
import SwiftUI
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureClipboard

/// The history at its backstop, 10,000 items of `ClipboardSeed`'s mix: the tab lays out without a stall, a search
/// comes back in about 100 ms. Debug builds, so the bounds are loose; the numbers are printed for the record.
@MainActor
struct ClipboardScaleTests {
  static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

  /// How much looser the time bounds are on CI (`CI` is set): a shared runner running every suite at once took 1.6 s
  /// for the first layout a Mac does in 12 ms. A stall still fails there, and a Mac, as before every push, keeps the
  /// tight bounds.
  static let slack = ProcessInfo.processInfo.environment["CI"] == nil ? 1 : 10

  /// The seed as the load gives it: long texts by their start, in `displayOrder`.
  static func loaded(_ seed: ClipboardSeed) -> IdentifiedArrayOf<ClipboardItem> {
    let items = seed.items.map { item -> ClipboardItem in
      var item = item
      if let text = item.content.text, let preview = ClipboardItem.preview(of: text) {
        item.content = .text(preview)
        item.isTruncated = true
      }
      return item
    }
    return IdentifiedArray(uniqueElements: items.sorted(by: ClipboardFeature.displayOrder))
  }

  func time(_ work: () throws -> Void) rethrows -> Duration {
    let start = ContinuousClock.now
    try work()
    return ContinuousClock.now - start
  }

  @Test
  func theTabWithTenThousandItemsLaysOutWithoutAStall() throws {
    let seed = ClipboardSeed(count: 10_000, images: 500, now: Self.now)
    var state = ClipboardFeature.State()
    state.items = Self.loaded(seed)
    state.isLoaded = true
    let store = Store(initialState: state) {
      ClipboardFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.date = .constant(Self.now)
      $0.database = VortexDatabase.inMemory()
      $0.fileClient.info = { _ in FileInfo(size: 1, isDirectory: false) }
      $0.uuid = .incrementing
    }
    let size = CGSize(width: VortexMetrics.windowSize.width - VortexMetrics.sidebarWidth, height: VortexMetrics.windowSize.height)
    let host = NSHostingView(rootView: ClipboardView(store: store).frame(width: size.width, height: size.height))
    let window = NSWindow(
      contentRect: CGRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.contentView = host

    func picture() -> Data? {
      guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
      host.cacheDisplay(in: host.bounds, to: bitmap)
      return bitmap.tiffRepresentation
    }
    /// How long until the tab shows something new: the run loop turns in 2 ms steps, the tab is laid out and drawn
    /// after each, until its picture changes. An upper bound: the steps and the pictures count too.
    func untilChanged(from previous: Data?) -> (Duration, Data?) {
      let start = ContinuousClock.now
      var current = previous
      while current == previous, ContinuousClock.now - start < .seconds(3) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.002))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        current = picture()
      }
      return (ContinuousClock.now - start, current)
    }
    let first = time {
      host.layoutSubtreeIfNeeded()
      host.displayIfNeeded()
    }
    let opened = picture()
    // A change to the history: the first card deleted, every card on screen moves.
    let top = try #require(store.items.first?.id)
    store.send(.deleteTapped(top))
    let (change, afterDelete) = untilChanged(from: opened)
    // Searched: the grid shows 3,000 of them.
    store.send(.queryChanged("seed"))
    store.send(.searched(Array(store.items.suffix(3_000).map(\.id))))
    let (results, searched) = untilChanged(from: afterDelete)
    print("10,000 items: first layout \(first); until the tab shows a delete \(change), 3,000 results \(results)")
    #expect(opened != nil && afterDelete != opened && searched != afterDelete)
    #expect(first < .seconds(1) * Self.slack)
    #expect(change < .milliseconds(250) * Self.slack)
    #expect(results < .milliseconds(250) * Self.slack)
    window.contentView = nil
  }

  @Test
  func aSearchOfTenThousandItemsComesBackInAbout100Milliseconds() throws {
    let database = VortexDatabase.inMemory()
    try ClipboardItem.migrator.migrate(database)
    let seed = ClipboardSeed(count: 10_000, images: 500, now: Self.now)
    let writing = try time {
      try database.write { db in _ = try HistoryWrite.apply(seed.items.map(HistoryWrite.insert), db) }
    }
    let bytes = try database.read { db in try Int.fetchOne(db, sql: "SELECT sum(length(CAST(searchText AS BLOB))) FROM clipboard_item") ?? 0 }
    var timings: [String] = []
    for query in ["release", "звіт київ", "token #42", "telegram", "nothing like this"] {
      let words = ClipboardFeature.searchWords(query)
      var found: [UUID] = []
      let took = try time {
        found = try database.read { db in try ClipboardItem.search(words, db) }
      }
      timings.append("\(query): \(found.count) in \(took)")
      #expect(took < .milliseconds(400) * Self.slack, "\(query)")
    }
    print("search over 10,000 items (\(bytes / 1_000_000) MB of search text, written in \(writing)): \(timings.joined(separator: "; "))")
  }
}
