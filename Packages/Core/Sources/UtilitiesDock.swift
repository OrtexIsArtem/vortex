import SwiftUI

/// A button of Home's utilities dock: one running utility action as the shell offers it, with its marks. Home draws it;
/// what a click does is the shell's (`UtilitiesDock.run`).
public struct UtilitiesDockButton: Identifiable, Equatable {
  /// The action's id, `<feature id>.<name>`.
  public var id: String
  /// The SF Symbol on its round button.
  public var symbol: String
  /// Its name, for VoiceOver and its tooltip: "Copy Text".
  public var label: LocalizedStringResource
  /// The keys of the action's shortcut, as the menus show them ("⌃⌥T"), which its tooltip names; nil while none is set.
  public var keys: String?
  /// The permission the action needs, while it reads `notGranted`: the button's yellow warning.
  public var warning: Permission?

  public init(
    id: String,
    symbol: String,
    label: LocalizedStringResource,
    keys: String? = nil,
    warning: Permission? = nil
  ) {
    self.id = id
    self.symbol = symbol
    self.label = label
    self.keys = keys
    self.warning = warning
  }
}

/// Home's utilities dock, as the shell gives it to Home's tab: the running utility actions, in catalog order, whether the
/// strip is out, and what the clicks do.
///
/// Home draws the button at the right end of its notch row, which is the pencil (Edit Home) itself while the dock has
/// no button, and the strip at the window's right: the buttons in one column, then the pencil, set apart. The shell owns
/// whether the strip is out, grows the window by it (`WindowSize.dock`), puts it away on the button again, Esc, a click
/// outside, another tab or the window closing, and runs what is chosen after making the window what it needs.
public struct UtilitiesDock {
  public var buttons: [UtilitiesDockButton]
  /// The strip is out at the window's right.
  public var isOpen: Bool
  /// The utilities button: the strip comes out, or goes.
  public var toggle: @MainActor () -> Void
  /// A click on Home outside the strip: it goes.
  public var close: @MainActor () -> Void
  /// A button of the strip, by its action's id: the strip goes, then the action runs as its shortcut runs it.
  public var run: @MainActor (_ id: String) -> Void

  public init(
    buttons: [UtilitiesDockButton],
    isOpen: Bool,
    toggle: @escaping @MainActor () -> Void,
    close: @escaping @MainActor () -> Void,
    run: @escaping @MainActor (_ id: String) -> Void
  ) {
    self.buttons = buttons
    self.isOpen = isOpen
    self.toggle = toggle
    self.close = close
    self.run = run
  }
}

extension EnvironmentValues {
  /// Home's utilities dock, from the shell; nil outside it, as in a preview, where Home's button is the pencil.
  @Entry public var utilitiesDock: UtilitiesDock? = nil
}
