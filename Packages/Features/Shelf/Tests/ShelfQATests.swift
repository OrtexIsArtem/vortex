import Foundation
import Testing
import VortexPlatform

@testable import FeatureShelf

/// QA mode's `shelf` command rests the pointer on a file as the tab and Home's widget show it.
@MainActor
struct ShelfQATests {
  let items = [
    ShelfItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, content: .text("one"), addedAt: .now),
    ShelfItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, content: .text("two"), addedAt: .now),
  ]

  /// The arguments as the QA channel hands them over: `key=value`, and a bare word as `word: ""`.
  func action(_ words: String) throws -> ShelfFeature.Action {
    var arguments: [String: String] = [:]
    for word in words.split(separator: " ") {
      let parts = word.split(separator: "=", maxSplits: 1)
      arguments[String(parts[0])] = parts.count > 1 ? String(parts[1]) : ""
    }
    return try ShelfModule.qaAction(arguments, items: items)
  }

  @Test
  func restSendsTheRestOnTheFileAtThatPlace() throws {
    #expect(try action("rest n=1") == .itemHoverRested(items[0].id))
    #expect(try action("rest n=2") == .itemHoverRested(items[1].id))
  }

  @Test
  func restWithoutAPlaceOnTheShelfIsRefused() {
    #expect(throws: QAError.self) { try action("rest") }
    #expect(throws: QAError.self) { try action("rest n=0") }
    #expect(throws: QAError.self) { try action("rest n=3") }
    #expect(throws: QAError.self) { try action("rest n=one") }
    #expect(throws: QAError.self) { try action("rest n=1 id=two") }
    #expect(throws: QAError.self) { try action("nap n=1") }
  }
}
