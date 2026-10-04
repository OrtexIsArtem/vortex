import ComposableArchitecture
import SwiftUI
import VortexCore

/// Entry point the app shell reads; registered in Features/Registry.
@MainActor
public enum ShelfModule: FeatureModule {
  public static let id: FeatureID = ShelfFeature.id
  public static let title = LocalizedStringResource("Shelf", bundle: .atURL(Bundle.module.bundleURL))
  public static let symbol = "tray"
  public static let acceptsFileDrops = true

  /// One store for the life of the app: files arrive and expire while the window is closed.
  static let store = Store(initialState: ShelfFeature.State()) {
    ShelfFeature()
  }

  public static func makeTab() -> AnyView {
    AnyView(ShelfView(store: store))
  }

  public static func setEnabled(_ isEnabled: Bool) {
    store.send(isEnabled ? .start : .stop)
  }

  public static func receiveFiles(_ urls: [URL]) {
    store.send(.filesReceived(urls))
  }
}
