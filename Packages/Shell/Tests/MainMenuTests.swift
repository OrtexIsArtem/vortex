import AppKit
import SwiftUI
import Testing

@testable import VortexPlatform
@testable import VortexShell

/// The main menu Vortex never shows: through its Edit menu the standard editing shortcuts reach windows Vortex doesn't
/// make, such as Quick Look's panel, as in any Mac app, while Vortex's own panels still send them first, once. Keys go
/// through AppKit as from the keyboard: to the key window, then to the main menu. The windows sit off every display and
/// never activate the test process; each test sets the main menu and puts the one before back.
@MainActor
struct MainMenuTests {
  /// What a press sent, by name: an editing action, Quit, or "unhandled", a key no one took, where AppKit would beep.
  /// It takes the actions as Quick Look's text does, from the responder chain; it takes Quit too, so a test never
  /// quits.
  final class Selection: NSView, NSMenuItemValidation {
    var sent: [String] = []
    /// Actions it says it can't do now, as a text with nothing selected can't copy.
    var refused: Set<Selector> = []

    override var acceptsFirstResponder: Bool { true }

    @objc(cut:) func cutAction(_ sender: Any?) { sent.append("cut") }
    @objc(copy:) func copyAction(_ sender: Any?) { sent.append("copy") }
    @objc(paste:) func pasteAction(_ sender: Any?) { sent.append("paste") }
    @objc(selectAll:) func selectAllAction(_ sender: Any?) { sent.append("selectAll") }
    @objc(undo:) func undoAction(_ sender: Any?) { sent.append("undo") }
    @objc(redo:) func redoAction(_ sender: Any?) { sent.append("redo") }
    @objc(terminate:) func terminateAction(_ sender: Any?) { sent.append("terminate") }
    override func keyDown(with event: NSEvent) { sent.append("unhandled") }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
      menuItem.action.map { !refused.contains($0) } ?? false
    }
  }

  /// A window Vortex doesn't make, as Quick Look's panel: nothing of its own maps the editing shortcuts.
  final class SystemPanel: NSPanel {
    override var canBecomeKey: Bool { true }
  }

  /// The shortcuts, by the Latin key and its key code, and the action each sends.
  static let shortcuts: [(key: String, code: UInt16, flags: NSEvent.ModifierFlags, sends: String)] = [
    ("x", 7, .command, "cut"),
    ("c", 8, .command, "copy"),
    ("v", 9, .command, "paste"),
    ("a", 0, .command, "selectAll"),
    ("z", 6, .command, "undo"),
    ("z", 6, [.command, .shift], "redo"),
  ]

  func key(_ characters: String, code: UInt16, _ flags: NSEvent.ModifierFlags, in window: NSWindow) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
      isARepeat: false, keyCode: code
    )
  }

  /// A window off every display with `selection` as its first responder, made key.
  func show(_ window: NSWindow, _ selection: Selection) {
    window.setFrame(CGRect(x: -20_000, y: -20_000, width: 300, height: 200), display: false)
    window.orderFrontRegardless()
    window.makeKey()
    window.makeFirstResponder(selection)
  }

  /// A system panel, made key, with a selection in it.
  func systemPanel() -> (SystemPanel, Selection) {
    let panel = SystemPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let selection = Selection(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    panel.contentView = selection
    show(panel, selection)
    return (panel, selection)
  }

  /// What one press sent, with `menu` as the app's main menu; nothing waits on the run loop, so no other test's window
  /// takes the keyboard meanwhile.
  func press(
    _ characters: String, code: UInt16, _ flags: NSEvent.ModifierFlags = .command, in window: NSWindow,
    _ selection: Selection, menu: NSMenu?
  ) throws -> [String] {
    let before = NSApp.mainMenu
    NSApp.mainMenu = menu
    defer { NSApp.mainMenu = before }
    window.makeKey()
    selection.sent = []
    NSApp.sendEvent(try #require(key(characters, code: code, flags, in: window)))
    return selection.sent
  }

  @Test
  func theEditingShortcutsReachAWindowVortexDoesntMake() throws {
    _ = NSApplication.shared
    let (panel, selection) = systemPanel()
    defer { panel.orderOut(nil) }
    // Without a main menu nothing turns ⌘C into Copy: Quick Look's text kept its selection to itself.
    #expect(try press("c", code: 8, in: panel, selection, menu: nil) == ["unhandled"])
    for shortcut in Self.shortcuts {
      let sent = try press(shortcut.key, code: shortcut.code, shortcut.flags, in: panel, selection, menu: MainMenu())
      #expect(sent == [shortcut.sends], "\(shortcut.flags.contains(.shift) ? "⇧" : "")⌘\(shortcut.key.uppercased())")
    }
  }

  /// Under a Cyrillic layout a key means what it types in the Latin layout the Mac uses for shortcuts, as in Vortex's
  /// panels (`EditingShortcuts`): ⌘С is ⌘C on QWERTY, QWERTZ and AZERTY, whichever of them this Mac has.
  @Test
  func underACyrillicLayoutTheKeysMeanTheirLatinOnes() throws {
    _ = NSApplication.shared
    let (panel, selection) = systemPanel()
    defer { panel.orderOut(nil) }
    for (cyrillic, code, flags) in [("ч", UInt16(7), NSEvent.ModifierFlags.command), ("с", 8, .command), ("м", 9, .command), ("ф", 0, .command), ("я", 6, .command), ("я", 6, [.command, .shift])] {
      let latin = try #require(EditingShortcuts.latinCharacter(keyCode: code))
      let asLatin = try press(latin, code: code, flags, in: panel, selection, menu: MainMenu())
      #expect(try press(cyrillic, code: code, flags, in: panel, selection, menu: MainMenu()) == asLatin, "\(cyrillic)")
    }
    #expect(try press("с", code: 8, in: panel, selection, menu: MainMenu()) == ["copy"])
  }

  /// The menu sends an action only where it can be done now, as any Mac app's Edit menu: a refused one is a key no one
  /// takes, where AppKit beeps.
  @Test
  func anActionTheWindowCantDoNowIsNotSent() throws {
    _ = NSApplication.shared
    let (panel, selection) = systemPanel()
    defer { panel.orderOut(nil) }
    selection.refused = [#selector(NSText.paste(_:))]
    #expect(try press("v", code: 9, in: panel, selection, menu: MainMenu()) == ["unhandled"])
    #expect(try press("c", code: 8, in: panel, selection, menu: MainMenu()) == ["copy"])
  }

  /// ⌘Q is as before the menu: Vortex's panels quit, through their own shortcuts; a system panel such as Quick Look's
  /// takes no ⌘Q.
  @Test
  func commandQIsAsItWas() throws {
    _ = NSApplication.shared
    let (system, inSystem) = systemPanel()
    defer { system.orderOut(nil) }
    #expect(try press("q", code: 12, in: system, inSystem, menu: MainMenu()) == ["unhandled"])
    #expect(try press("q", code: 12, in: system, inSystem, menu: nil) == ["unhandled"])

    let root = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    let inVortex = Selection(frame: root.bounds)
    root.addSubview(inVortex)
    let panel = VortexPanel(acceptsKey: true, root: root, content: Color.clear)
    show(panel, inVortex)
    defer { panel.orderOut(nil) }
    #expect(try press("q", code: 12, in: panel, inVortex, menu: MainMenu()) == ["terminate"])
    #expect(try press("й", code: 12, in: panel, inVortex, menu: MainMenu()) == ["terminate"])
  }

  /// Vortex's own panels send the shortcuts themselves, first: with the menu there too, each press does its action
  /// once, also under a Cyrillic layout.
  @Test
  func vortexPanelsStillSendEachShortcutOnce() throws {
    _ = NSApplication.shared
    let root = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
    let selection = Selection(frame: root.bounds)
    root.addSubview(selection)
    let panel = VortexPanel(acceptsKey: true, root: root, content: Color.clear)
    show(panel, selection)
    defer { panel.orderOut(nil) }
    for shortcut in Self.shortcuts {
      let sent = try press(shortcut.key, code: shortcut.code, shortcut.flags, in: panel, selection, menu: MainMenu())
      #expect(sent == [shortcut.sends], "\(shortcut.flags.contains(.shift) ? "⇧" : "")⌘\(shortcut.key.uppercased())")
    }
    #expect(try press("м", code: 9, in: panel, selection, menu: MainMenu()) == ["paste"])
  }

  /// The menu has the standard Edit items, so AppKit and the system find them where they look.
  @Test
  func theEditMenuHasTheStandardItems() throws {
    let menu = MainMenu()
    let edit = try #require(menu.items.compactMap(\.submenu).first { $0.items.contains { $0.action == #selector(NSText.copy(_:)) } })
    let items = edit.items.filter { !$0.isSeparatorItem }.map { ($0.action.map(NSStringFromSelector) ?? "", $0.keyEquivalent, $0.keyEquivalentModifierMask) }
    #expect(items.map(\.0) == ["undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:"])
    #expect(items.map(\.1) == ["z", "Z", "x", "c", "v", "a"])
    #expect(items.allSatisfy { $0.2 == .command })
    // No Quit: ⌘Q stays the panels'.
    #expect(!menu.items.flatMap { $0.submenu?.items ?? [] }.contains { $0.action == #selector(NSApplication.terminate(_:)) })
  }
}
