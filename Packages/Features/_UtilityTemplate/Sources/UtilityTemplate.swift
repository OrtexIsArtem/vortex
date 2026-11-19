import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

extension Hotkey {
  /// Runs the template's action. None by default; the shell records it on the utility's page in Settings › Features and
  /// listens for it, through the utility action. Name it after what it does: KeyboardShortcuts stores the keys under it.
  static let sayHello = Hotkey("sayHello")
}

/// Entry point the app shell reads. Register it in Features/Registry.
///
/// A utility does one clear thing and has no tab: its button is in Home's utilities dock, and the shell runs it there
/// and from its shortcut, after making the window what its action needs. This one says hello in the closed notch.
@MainActor
public enum UtilityTemplateModule: FeatureModule {
  public static let id: FeatureID = UtilityTemplateFeature.id
  public static let title = LocalizedStringResource("Utility Template", bundle: .atURL(Bundle.module.bundleURL))
  public static let symbol = "hand.wave"
  public static let kind = FeatureKind.utility
  public static let summary = LocalizedStringResource("A starting point for a new utility", bundle: .atURL(Bundle.module.bundleURL))
  public static let details = LocalizedStringResource("Copy this folder to start a utility of your own: one clear action, with a button in Home's utilities dock and a shortcut.", bundle: .atURL(Bundle.module.bundleURL))
  public static let author = "@OrtexIsArtem"

  /// One store for the life of the app: the shortcut works while the window is closed.
  static let store = Store(initialState: UtilityTemplateFeature.State()) {
    UtilityTemplateFeature()
  }

  /// The one action: its symbol, label and help for its button and tooltip, what the window must be first, the
  /// permission its warning names (none here) and the shortcut that runs it. The shell closes the window first, as the
  /// hello shows in the closed notch.
  public static func makeUtilityActions() -> [UtilityAction] {
    [
      UtilityAction(
        id: "\(id).hello",
        feature: id,
        symbol: symbol,
        label: LocalizedStringResource("Say Hello", bundle: .atURL(Bundle.module.bundleURL)),
        help: LocalizedStringResource("Say hello in the notch", bundle: .atURL(Bundle.module.bundleURL)),
        window: .closed,
        shortcut: Hotkey.sayHello.name
      ) {
        store.send(.sayHello)
      },
    ]
  }

  /// A stopped utility takes its indicator away; the shell also hides the indicators of features that don't run.
  public static func setEnabled(_ isEnabled: Bool) {
    if !isEnabled { store.send(.helloEnded) }
  }
}

/// The template's one action: "Hello" in the closed notch's ears for a moment.
@Reducer
public struct UtilityTemplateFeature: Sendable {
  static let id: FeatureID = "utilitytemplate"
  /// How long the hello shows.
  static let moment: Duration = .milliseconds(1500)
  /// What the notch shows meanwhile.
  static let hello = NotchIndicator(leading: [.symbol("hand.wave")], trailing: [.text("Hello")])

  @ObservableState
  public struct State: Equatable {
    /// Its own entry in the closed notch's indicators, and only its own.
    @Shared(.notchIndicators) var indicators

    public init() {}
  }

  public enum Action: Equatable {
    case sayHello
    case helloEnded
  }

  @Dependency(\.continuousClock) var clock

  private enum CancelID {
    case hello
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .sayHello:
        state.$indicators.withLock { $0[Self.id] = Self.hello }
        // A new press starts the moment again.
        return .run { send in
          try await clock.sleep(for: Self.moment)
          await send(.helloEnded)
        }
        .cancellable(id: CancelID.hello, cancelInFlight: true)

      case .helloEnded:
        state.$indicators.withLock { $0[Self.id] = nil }
        return .cancel(id: CancelID.hello)
      }
    }
  }
}
