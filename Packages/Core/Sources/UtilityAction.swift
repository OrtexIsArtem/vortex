import Foundation

/// A one-click action a feature offers as a utility, such as copying the text in a frame on the screen. A feature
/// offers one or two (`FeatureModule.makeUtilityActions()`). The shell places them and runs them, from a click or from
/// the action's shortcut alike, after it has made the window what the action needs: a feature never decides where its
/// button goes, and never opens or closes the window itself.
public struct UtilityAction: Identifiable {
  /// What the window must be when the action runs. The shell sees to it first.
  public enum WindowNeed: Equatable, Sendable {
    /// Out of the way: the shell closes its window, then runs the action, as one that works on the screen needs.
    case closed
    /// Open and showing, as an action whose own screen covers the window, such as keyboard cleaning's lock, needs.
    case open
    /// Either: the window stays as it is.
    case unchanged
  }

  /// `<feature id>.<name>`.
  public let id: String
  public let feature: FeatureID
  /// SF Symbol on its button.
  public let symbol: String
  /// The button's name, for VoiceOver and wherever the shell writes it: "Copy Text".
  public let label: LocalizedStringResource
  /// Its tooltip, which says what a click does: "Copy text from the screen".
  public let help: LocalizedStringResource
  public let window: WindowNeed
  /// The macOS permission the action needs, if any: where the shell places the button, it marks it while that
  /// permission reads `notGranted`, as a sidebar icon's yellow dot.
  public let permission: Permission?
  /// The name of the feature's own shortcut that runs the action (its `Hotkey`), which the feature records on its
  /// settings page; nil without one. The shell listens for it while the feature runs and runs the action as a click
  /// does, so the feature doesn't listen for it itself.
  public let shortcut: String?
  /// What a click does, run by the shell once the window is as `window` says.
  public let perform: @MainActor () -> Void

  public init(
    id: String,
    feature: FeatureID,
    symbol: String,
    label: LocalizedStringResource,
    help: LocalizedStringResource,
    window: WindowNeed,
    permission: Permission? = nil,
    shortcut: String? = nil,
    perform: @escaping @MainActor () -> Void
  ) {
    self.id = id
    self.feature = feature
    self.symbol = symbol
    self.label = label
    self.help = help
    self.window = window
    self.permission = permission
    self.shortcut = shortcut
    self.perform = perform
  }

  /// The action without its words and what it does: what the shell keeps in its state.
  public var info: UtilityActionInfo {
    UtilityActionInfo(id: id, feature: feature, window: window, shortcut: shortcut)
  }

  /// What's wrong with a feature's actions, empty when nothing is: at most two, ids `<feature>.<name>` and each once,
  /// no shortcut shared.
  public static func problems(_ actions: [UtilityAction], feature: FeatureID) -> [String] {
    var problems: [String] = []
    if actions.count > 2 { problems.append("\(feature) offers \(actions.count) utility actions; at most 2") }
    var ids: Set<String> = []
    var shortcuts: Set<String> = []
    for action in actions {
      if !action.id.hasPrefix("\(feature).") || action.id.count <= feature.count + 1 {
        problems.append("\(action.id) doesn't start with \(feature).")
      }
      if !ids.insert(action.id).inserted { problems.append("\(action.id) is there twice") }
      if let shortcut = action.shortcut, !shortcuts.insert(shortcut).inserted {
        problems.append("\(action.id) shares the shortcut \(shortcut)")
      }
    }
    return problems
  }
}

/// A utility action as plain data, safe to keep in reducer state: see `UtilityAction`.
public struct UtilityActionInfo: Equatable, Sendable {
  public var id: String
  public var feature: FeatureID
  public var window: UtilityAction.WindowNeed
  public var shortcut: String?

  public init(id: String, feature: FeatureID, window: UtilityAction.WindowNeed, shortcut: String? = nil) {
    self.id = id
    self.feature = feature
    self.window = window
    self.shortcut = shortcut
  }
}
