import Foundation
import Testing

@testable import FeatureClipboard

/// Home's rows: at most 10 pinned items, then the newest unpinned ones, 20 rows in all.
extension ClipboardFeatureTests {
  /// A history of `pinned` pinned items and `copies` other ones, each newest first.
  func homeState(pinned: Int, copies: Int) -> ClipboardFeature.State {
    var state = ClipboardFeature.State()
    let newest = now.value
    state.items = history(
      (0..<pinned).map { item("pinned \($0)", id: 1_000 + $0, copiedAt: newest - Double($0), isPinned: true) }
        + (0..<copies).map { item("copy \($0)", id: 2_000 + $0, copiedAt: newest - Double($0)) }
    )
    return state
  }

  func texts(_ prefix: String, _ count: Int) -> [ClipboardItem.Content] {
    (0..<count).map { .text("\(prefix) \($0)") }
  }

  @Test
  func homeShowsTheNewestTenPinnedItemsThenTheNewestCopies() {
    let state = homeState(pinned: 25, copies: 30)
    #expect(state.homeItems.map(\.content) == texts("pinned", 10) + texts("copy", 10))
    // The tab still shows every pin.
    #expect(state.shownItems.filter(\.isPinned).count == 25)
    #expect(homeState(pinned: 3, copies: 100).homeItems.map(\.content) == texts("pinned", 3) + texts("copy", 17))
  }

  @Test
  func pinsPastTheTenthStayOffHomeEvenWithRoom() {
    let state = homeState(pinned: 15, copies: 3)
    #expect(state.homeItems.map(\.content) == texts("pinned", 10) + texts("copy", 3))
    #expect(state.shownItems.filter(\.isPinned).count == 15)
  }

  @Test
  func withoutPinsHomeShowsTheNewestTwenty() {
    #expect(homeState(pinned: 0, copies: 30).homeItems.map(\.content) == texts("copy", 20))
    #expect(homeState(pinned: 0, copies: 5).homeItems.map(\.content) == texts("copy", 5))
    #expect(homeState(pinned: 0, copies: 0).homeItems.isEmpty)
  }
}
