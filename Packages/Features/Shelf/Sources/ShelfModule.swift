import ComposableArchitecture
import SwiftUI
import VortexCore

/// Entry point the app shell reads; registered in Features/Registry.
@MainActor
public enum ShelfModule: FeatureModule {
  public static let id: FeatureID = ShelfFeature.id
  public static let title = LocalizedStringResource("Shelf", bundle: .atURL(Bundle.module.bundleURL))
  public static let symbol = "tray"
  public static let summary = LocalizedStringResource("Files put aside to drag into other apps", bundle: .atURL(Bundle.module.bundleURL))
  public static let details = LocalizedStringResource("Put files aside while you switch apps, then drag them where they go. Files dragged onto the notch land here too.", bundle: .atURL(Bundle.module.bundleURL))
  public static let author = "@OrtexIsArtem"
  public static let isRecommended = true
  public static let keeps: LocalizedStringResource? = LocalizedStringResource("Copies of the files on the shelf.", bundle: .atURL(Bundle.module.bundleURL))
  public static let dataFolder: String? = "Shelf"
  /// The files in Resources/Catalog/, which the build copies to the top of the bundle, without the folder.
  public static let preview: FeaturePreview? = FeaturePreview(
    video: Bundle.module.url(forResource: "preview", withExtension: "mov"),
    still: Bundle.module.url(forResource: "still", withExtension: "jpg")
  )
  public static let acceptsFileDrops = true

  /// One store for the life of the app: files arrive and expire while the window is closed.
  static let store = Store(initialState: ShelfFeature.State()) {
    ShelfFeature()
  }

  public static func makeTab() -> AnyView {
    AnyView(ShelfView(store: store))
  }

  public static func makeSettings() -> AnyView? {
    AnyView(ShelfSettingsView(store: store))
  }

  public static func makeHomeWidgets() -> [HomeWidget] {
    [
      HomeWidget(
        id: "shelf.files",
        feature: id,
        title: LocalizedStringResource("Files", bundle: .atURL(Bundle.module.bundleURL)),
        // Large first, the size Home's first layout gives it: the shelf as Home had it before its grid, half the width
        // and the full height.
        place: .grid([.large, .medium, .wide]),
        view: ShelfHomeWidget(store: store)
      ),
    ]
  }

  public static func setEnabled(_ isEnabled: Bool) {
    #if DEBUG
      registerQACommands()
    #endif
    store.send(isEnabled ? .start : .stop)
  }

  public static func receiveFiles(_ urls: [URL]) {
    store.send(.filesReceived(urls))
  }
}
