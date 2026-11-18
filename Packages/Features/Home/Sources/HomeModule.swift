import ComposableArchitecture
import SwiftUI
import VortexCore

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
}
