import SwiftUI
import VortexCore

/// Entry point the app shell reads; registered in Features/Registry. Home has no state of its own: it shows the
/// widgets of the other features, which the shell hands over in `homeWidgets`.
@MainActor
public enum HomeModule: FeatureModule {
  public static let id: FeatureID = "home"
  public static let title = LocalizedStringResource("Home", bundle: .atURL(Bundle.module.bundleURL))
  public static let symbol = "square.grid.2x2"

  public static func makeTab() -> AnyView {
    AnyView(HomeView())
  }
}
