import AppKit

/// Vortex has no main menu, so nothing maps the standard editing shortcuts; its panels send them themselves.
public enum EditingShortcuts {
  /// The action for ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z, ⇧⌘Z and ⌘Q; nil for any other key.
  public static func action(for event: NSEvent) -> Selector? {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let isShifted = flags == [.command, .shift]
    guard flags == .command || isShifted else { return nil }
    switch (event.charactersIgnoringModifiers?.lowercased(), isShifted) {
    case ("x", false): return #selector(NSText.cut(_:))
    case ("c", false): return #selector(NSText.copy(_:))
    case ("v", false): return #selector(NSText.paste(_:))
    case ("a", false): return #selector(NSText.selectAll(_:))
    case ("z", false): return Selector(("undo:"))
    case ("z", true): return Selector(("redo:"))
    case ("q", false): return #selector(NSApplication.terminate(_:))
    default: return nil
    }
  }
}
