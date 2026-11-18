import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// Entry point the app shell reads; registered in Features/Registry. Home lays out the widgets of the other features,
/// which the shell hands over in `homeWidgets`, and keeps where they are in home.json.
@MainActor
public enum HomeModule: FeatureModule {
  public static let id: FeatureID = "home"
  public static let title = LocalizedStringResource("Home", bundle: .atURL(Bundle.module.bundleURL))
  public static let symbol = "square.grid.2x2"
  public static let summary = LocalizedStringResource("Your widgets in one place", bundle: .atURL(Bundle.module.bundleURL))
  public static let details = LocalizedStringResource("Home lays out the widgets of the features you added and the button that locks the keyboard for cleaning.", bundle: .atURL(Bundle.module.bundleURL))
  public static let author = "@OrtexIsArtem"
  public static let isBuiltIn = true

  /// One store for the life of the app: the layout outlives the window.
  static let store = Store(initialState: HomeFeature.State()) {
    HomeFeature()
  }

  public static func makeTab() -> AnyView {
    AnyView(HomeView(store: store))
  }

  public static func setEnabled(_ isEnabled: Bool) {
    #if DEBUG
      // A QA run takes commands only on its own channel (VortexPlatform's `QA`).
      if QA.isActive, !hasQACommands {
        hasQACommands = true
        registerQACommands()
      }
    #endif
  }

  #if DEBUG
    private static var hasQACommands = false

    /// QA mode: `home edit|done` opens and ends the editor, as the pencil and Done do, while the window shows Home.
    private static func registerQACommands() {
      QA.register(command: "home") { arguments in
        guard QA.isShowing(.tab(id)) else { throw QAError("Home's commands work while the open window shows Home") }
        if arguments["edit"] != nil {
          store.send(.editTapped)
        } else if arguments["done"] != nil {
          store.send(.doneTapped)
        } else {
          throw QAError("home takes edit or done")
        }
      }
    }
  #endif
}
