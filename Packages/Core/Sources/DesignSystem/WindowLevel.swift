import AppKit

extension NSWindow.Level {
  /// The notch window and its ears: above the menu bar, so they can cover the notch.
  public static let vortex = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
  /// Panels opened over the Vortex window, such as Quick Look and the folder picker.
  public static let aboveVortex = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
}
