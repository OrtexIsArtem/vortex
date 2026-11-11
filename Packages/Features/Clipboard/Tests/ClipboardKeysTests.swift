import AppKit
import ComposableArchitecture
import Foundation
import SwiftUI
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureClipboard

/// The keys of the search field, through AppKit as in the window: ⌘F focuses it, Esc empties it, and Esc in an empty
/// field goes on to the window, whose `cancelOperation` closes it. The tab sits in a panel off every display that never
/// activates the test process, so nothing on screen changes.
@MainActor
struct ClipboardKeysTests {
  /// Counts the Esc that reaches the window, where Vortex's panel closes.
  final class Panel: NSPanel {
    var escapes = 0
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { escapes += 1 }
  }

  func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, characters: characters,
      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
    )
  }

  /// Lets SwiftUI apply what changed, until the condition holds or two seconds pass.
  func eventually(_ condition: () -> Bool) -> Bool {
    let start = ContinuousClock.now
    while !condition(), ContinuousClock.now - start < .seconds(2) {
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return condition()
  }

  @Test
  func commandFFocusesTheFieldAndEscEmptiesItThenClosesTheWindow() throws {
    var state = ClipboardFeature.State()
    state.isLoaded = true
    let store = Store(initialState: state) {
      ClipboardFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.database = VortexDatabase.inMemory()
    }
    let panel = Panel(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 624, height: 440),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.contentView = NSHostingView(rootView: ClipboardView(store: store).frame(width: 624, height: 440))
    panel.orderFrontRegardless()
    panel.makeKey()
    defer { panel.orderOut(nil) }
    var fieldIsFocused: Bool { panel.firstResponder is NSTextView }

    /// A person's keys come one run loop turn after another, each after the tab is drawn again.
    func settle() {
      RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    }
    settle()
    for (character, layout) in [("f", "Latin"), ("а", "Ukrainian")] {
      panel.makeFirstResponder(nil)
      #expect(eventually { !fieldIsFocused })
      settle()
      // The F key, as AppKit hands a key equivalent to the window.
      let commandF = try #require(key(character, code: 3, modifiers: .command, in: panel))
      #expect(panel.performKeyEquivalent(with: commandF), "\(layout)")
      #expect(eventually { fieldIsFocused }, "\(layout)")
    }

    (panel.firstResponder as? NSTextView)?.insertText("release", replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(eventually { store.query == "release" })
    settle()
    let escape = try #require(key("\u{1b}", code: 53, in: panel))
    panel.sendEvent(escape)
    #expect(eventually { store.query.isEmpty })
    settle()
    #expect(panel.escapes == 0)
    panel.sendEvent(escape)
    #expect(eventually { panel.escapes == 1 })
  }

  /// The search field's width: it fills the header right of the notch, so the Clear beside it takes from it. It is the
  /// tab's only text field; its text is drawn by SwiftUI, not AppKit.
  func searchFieldWidth(in view: NSView) -> CGFloat? {
    if let field = view as? NSTextField { return field.frame.width }
    return view.subviews.lazy.compactMap { searchFieldWidth(in: $0) }.first
  }

  @Test
  func theTabShowsClearForAQueryOfSpacesAndHidesItForAWord() throws {
    var state = ClipboardFeature.State()
    state.items = [ClipboardItem(id: UUID(), content: .text("notes"), source: nil, copiedAt: .now, fingerprint: "a")]
    state.isLoaded = true
    let store = Store(initialState: state) {
      ClipboardFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.database = VortexDatabase.inMemory()
    }
    let panel = Panel(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 624, height: 440),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    let host = NSHostingView(rootView: ClipboardView(store: store).frame(width: 624, height: 440))
    panel.contentView = host
    panel.orderFrontRegardless()
    defer { panel.orderOut(nil) }
    /// The field's width once SwiftUI has drawn the query the store holds now.
    func width(for query: String) throws -> CGFloat {
      store.send(.queryChanged(query))
      RunLoop.main.run(until: Date().addingTimeInterval(0.3))
      host.layoutSubtreeIfNeeded()
      return try #require(searchFieldWidth(in: host))
    }

    // Both queries leave text in the field, so its own clear button shows for both: only the tab's Clear differs.
    let withSpaces = try width(for: "   ")
    let withWord = try width(for: "notes")
    // Only spaces: no search is shown, so Clear stands beside the field. A word: a search, and Clear goes.
    #expect(withWord - withSpaces > 40, "the field is \(withSpaces) pt with spaces, \(withWord) pt with a word")
    // And back: spaces again bring Clear back.
    #expect(try width(for: "  ") == withSpaces)
  }
}
