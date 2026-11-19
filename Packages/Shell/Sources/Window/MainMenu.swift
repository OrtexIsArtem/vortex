import AppKit
import VortexPlatform

/// The app's main menu, which never shows: Vortex has no menu bar (LSUIElement). AppKit still hands it every key
/// equivalent the key window leaves, so its Edit menu makes ⌘X ⌘C ⌘V ⌘A ⌘Z and ⇧⌘Z work in windows Vortex doesn't
/// make, such as Quick Look's panel, whose text takes Copy and Select All only as actions sent by an Edit menu.
///
/// Vortex's own panels send these shortcuts themselves (`EditingShortcuts`), and AppKit asks the key window before the
/// menu, so a press there never acts twice. There is no Quit: ⌘Q stays the panels' and the onboarding window's.
final class MainMenu: NSMenu {
  init() {
    super.init(title: "")
    // The first item is the app's menu, wherever a menu bar would show it; the Edit menu comes after it.
    let app = NSMenuItem()
    app.submenu = NSMenu()
    addItem(app)
    let comment: StaticString = "The Edit menu, which never shows: macOS's own name"
    let edit = NSMenu(title: String(localized: "Edit", bundle: .module, comment: comment))
    // An uppercase key equivalent takes Shift, as in AppKit's own menus.
    let items: [(String, Selector, String)] = [
      (String(localized: "Undo", bundle: .module, comment: comment), Selector(("undo:")), "z"),
      (String(localized: "Redo", bundle: .module, comment: comment), Selector(("redo:")), "Z"),
      (String(localized: "Cut", bundle: .module, comment: comment), #selector(NSText.cut(_:)), "x"),
      (String(localized: "Copy", bundle: .module, comment: comment), #selector(NSText.copy(_:)), "c"),
      (String(localized: "Paste", bundle: .module, comment: comment), #selector(NSText.paste(_:)), "v"),
      (String(localized: "Select All", bundle: .module, comment: comment), #selector(NSText.selectAll(_:)), "a"),
    ]
    for (index, (title, action, key)) in items.enumerated() {
      if index == 2 { edit.addItem(.separator()) }
      // No target: the action goes to whatever has the keyboard, the key window's first responder and on along its
      // chain.
      edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
    }
    let editItem = NSMenuItem(title: edit.title, action: nil, keyEquivalent: "")
    editItem.submenu = edit
    addItem(editItem)
  }

  @available(*, unavailable)
  required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  /// The keys read as Vortex's panels read them (`EditingShortcuts`), so under a Cyrillic layout ⌘С is Copy, whichever
  /// input source macOS has selected. An action goes only where the key window can do it now, as from any Edit menu;
  /// otherwise the key goes on as one nobody took. A key that is no item's, ⌘Q among them, is AppKit's to match: no item
  /// takes ⌘Q, as before this menu.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard let action = EditingShortcuts.action(for: event),
          let menu = items.lazy.compactMap(\.submenu).first(where: { $0.items.contains { $0.action == action } }),
          let index = menu.items.firstIndex(where: { $0.action == action })
    else { return super.performKeyEquivalent(with: event) }
    menu.update()
    guard menu.items[index].isEnabled else { return false }
    menu.performActionForItem(at: index)
    return true
  }
}
