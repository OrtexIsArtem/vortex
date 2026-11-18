import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// Entry point the app shell reads; registered in Features/Registry.
@MainActor
public enum ClipboardModule: FeatureModule {
  public static let id: FeatureID = "clipboard"
  public static let title = LocalizedStringResource("Clipboard", bundle: .atURL(Bundle.module.bundleURL))
  public static let symbol = "doc.on.clipboard"
  public static let summary = LocalizedStringResource("Everything you copied, searchable", bundle: .atURL(Bundle.module.bundleURL))
  public static let details = LocalizedStringResource("Keeps what you copy for a week, a month or as long as you choose. Search finds text, links and even the words in a screenshot. Pin what you reuse.", bundle: .atURL(Bundle.module.bundleURL))
  public static let author = "@OrtexIsArtem"
  public static let isRecommended = true
  public static let keeps: LocalizedStringResource? = LocalizedStringResource("Clipboard history and pinned items.", bundle: .atURL(Bundle.module.bundleURL))
  public static let dataFolder: String? = "Clipboard"
  public static let permissionNeeds = [
    PermissionNeed(
      .pasteboard,
      reason: LocalizedStringResource("Keeps your clipboard history.", bundle: .atURL(Bundle.module.bundleURL))
    ),
  ]

  /// One store for the life of the app: the history keeps recording while the window is closed.
  static let store = Store(initialState: ClipboardFeature.State()) {
    ClipboardFeature()
  }

  public static func makeTab() -> AnyView {
    AnyView(ClipboardView(store: store))
  }

  public static func makeSettings() -> AnyView? {
    AnyView(ClipboardSettingsView(store: store))
  }

  public static func makeHomeWidgets() -> [HomeWidget] {
    [
      HomeWidget(
        id: "clipboard.history",
        feature: id,
        title: LocalizedStringResource("History", bundle: .atURL(Bundle.module.bundleURL)),
        place: .grid([.large, .medium]),
        view: ClipboardHomeWidget(store: store)
      ),
    ]
  }

  public static func setEnabled(_ isEnabled: Bool) {
    #if DEBUG
      registerQACommands()
    #endif
    store.send(isEnabled ? .start : .stop)
  }
}
