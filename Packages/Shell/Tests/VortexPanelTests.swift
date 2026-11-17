import AppKit
import SwiftUI
import Testing
import VortexCore

@testable import VortexShell

/// A panel stuck on another Space is replaced by a new one (`VortexPanel.replacement`): the new panel takes the old
/// one's content as it is and is set up the same way.
@MainActor
struct VortexPanelTests {
  @Test func replacementTakesTheContentAndTheSetup() {
    let root = NSView()
    let old = VortexPanel(acceptsKey: true, root: root, content: Color.clear)
    var escapes = 0
    old.onEscape = { escapes += 1 }
    // Not the default, so the test sees it copied (a visible QA run's window lets the pointer through).
    old.ignoresMouseEvents = true
    old.hasShadow = true
    old.setFrame(CGRect(x: 100, y: 200, width: 700, height: 440), display: false)
    let hosting = root.subviews.first

    let new = old.replacement()

    #expect(new !== old)
    #expect(new.contentView === root)
    #expect(root.subviews.first === hosting)
    #expect(hosting is NSHostingView<Color>)
    #expect(old.contentView !== root)
    #expect(new.frame == CGRect(x: 100, y: 200, width: 700, height: 440))
    #expect(new.level == .vortex)
    #expect(new.collectionBehavior == old.collectionBehavior)
    #expect(new.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(new.styleMask == old.styleMask)
    #expect(new.ignoresMouseEvents)
    #expect(new.hasShadow)
    #expect(new.canBecomeKey)
    new.cancelOperation(nil)
    #expect(escapes == 1)
  }

  @Test func replacementKeepsTheKeyboardFocus() {
    let root = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    let focusable = FocusableView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
    root.addSubview(focusable)
    let old = VortexPanel(acceptsKey: true, root: root, content: Color.clear)
    #expect(old.makeFirstResponder(focusable))

    let new = old.replacement()

    #expect(new.firstResponder === focusable)
  }

  @Test func replacementKeepsTheFocusOnATextFieldBeingEdited() {
    let root = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 200, height: 24))
    root.addSubview(field)
    let old = VortexPanel(acceptsKey: true, root: root, content: Color.clear)
    #expect(old.makeFirstResponder(field))
    // Editing hands the focus to the window's field editor, whose delegate is the field.
    #expect((old.firstResponder as? NSText)?.delegate === field)

    let new = old.replacement()

    #expect((new.firstResponder as? NSText)?.delegate === field || new.firstResponder === field)
  }

  @Test func replacementOfAPanelThatTakesNoKeysTakesNone() {
    let old = VortexPanel(acceptsKey: false, root: NSView(), content: Color.clear)
    #expect(!old.replacement().canBecomeKey)
  }
}

private final class FocusableView: NSView {
  override var acceptsFirstResponder: Bool { true }
}
