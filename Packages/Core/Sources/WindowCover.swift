import ComposableArchitecture
import SwiftUI

/// A utility's screen over the whole window while it works, such as keyboard cleaning's lock screen. The utility puts it
/// up and takes it down in `@Shared(.windowCover)`, from its reducer; the shell draws its view
/// (`FeatureModule.makeWindowCover()`) over the sidebar and the tab, and keeps the window meanwhile:
/// - the window stays open: the pointer leaving, a click outside, Esc, the notch, the menu bar icon and the shortcuts
///   close nothing, an action that needs the window closed doesn't run, and new displays move the window there;
/// - a permission that goes blocks Vortex only once the cover is down;
/// - when the cover goes, the window closes with it;
/// - a utility that stops (turned off, removed, paused) with its cover still up loses it: the shell takes it down, and
///   the window closes. A crash takes it too, as the cover lives in memory.
///
/// A utility whose action puts up a cover asks for the window open (`UtilityAction.WindowNeed.open`): the shell opens it
/// first, and opens it too for a cover that comes while it is closed.
public struct WindowCover: Equatable, Sendable {
  /// The utility whose cover it is, and whose view shows.
  public var feature: FeatureID
  /// While the cover shows, Vortex keeps the front and its window the keyboard, and drops every key that reaches it, so
  /// one that gets past a keyboard lock goes nowhere else; it still reaches the lock's own presses
  /// (`KeyboardLockClient.reportPassed`). The app that was in front gets the front and the keys back as the cover goes.
  public var holdsKeyboard: Bool

  public init(feature: FeatureID, holdsKeyboard: Bool = false) {
    self.feature = feature
    self.holdsKeyboard = holdsKeyboard
  }
}

extension SharedReaderKey where Self == InMemoryKey<WindowCover?>.Default {
  /// The cover over the window now; nil while none shows. The utility whose cover it is writes it: as its work starts,
  /// and back to nil as it ends, however it ends. The shell writes nil only for a utility that stopped with it up.
  public static var windowCover: Self {
    Self[.inMemory("windowCover"), default: nil]
  }
}
