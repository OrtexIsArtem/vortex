import Foundation
import Testing
import VortexPlatform

@testable import FeatureClipboard

/// QA mode's `clipboard card n= do=` sends what the card's views send.
@MainActor
struct ClipboardQATests {
  @Test
  func aCardCommandSendsWhatTheCardSends() throws {
    var pinned = ClipboardItem(id: UUID(), content: .text("pinned"), source: nil, copiedAt: .now, fingerprint: "a")
    pinned.isPinned = true
    var long = ClipboardItem(id: UUID(), content: .text("the start"), source: nil, copiedAt: .now, fingerprint: "b")
    long.isTruncated = true
    let short = ClipboardItem(id: UUID(), content: .text("short"), source: nil, copiedAt: .now, fingerprint: "c")
    let shown = [pinned, long, short]
    func action(_ place: Int, _ pointer: String) throws -> ClipboardFeature.Action? {
      try ClipboardModule.cardAction(["card": "", "n": "\(place)", "do": pointer], shown: shown)
    }

    #expect(try action(3, "click") == .itemTapped(short.id))
    #expect(try action(2, "hover") == .itemHovered(long.id))
    // A short text has nothing to read on hover, and leaving a card sends nothing.
    #expect(try action(3, "hover") == nil)
    #expect(try action(2, "unhover") == nil)
    #expect(try action(3, "pin") == .pinTapped(short.id))
    #expect(try action(1, "unpin") == .pinTapped(pinned.id))
    #expect(try action(1, "delete") == .deleteTapped(pinned.id))
    // Only the button that shows can be pressed, only on a card that is shown.
    #expect(throws: QAError.self) { try action(1, "pin") }
    #expect(throws: QAError.self) { try action(3, "unpin") }
    #expect(throws: QAError.self) { try action(0, "click") }
    #expect(throws: QAError.self) { try action(4, "click") }
    #expect(throws: QAError.self) { try action(1, "drag") }
  }
}
