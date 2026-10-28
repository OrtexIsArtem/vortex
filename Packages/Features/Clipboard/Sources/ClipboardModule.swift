import ComposableArchitecture
import SwiftUI
import VortexCore

/// Entry point the app shell reads; registered in Features/Registry.
@MainActor
public enum ClipboardModule: FeatureModule {
  public static let id: FeatureID = "clipboard"
  public static let title = LocalizedStringResource("Clipboard", bundle: .atURL(Bundle.module.bundleURL))
  public static let symbol = "doc.on.clipboard"
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

  public static func makeHomeWidget() -> HomeWidget? {
    HomeWidget(id: id, slot: .dock, view: ClipboardHomeWidget(store: store))
  }

  public static func setEnabled(_ isEnabled: Bool) {
    store.send(isEnabled ? .start : .stop)
  }
}
