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
}
