import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// Entry point the app shell reads; registered in Features/Registry. A utility: its whole look is the lock screen over
/// the window, its button in Home's utilities dock and its settings.
@MainActor
public enum KeyboardCleaningModule: FeatureModule {
  public static let id: FeatureID = KeyboardCleaningFeature.id
  public static let title = LocalizedStringResource("Keyboard Cleaning", bundle: .atURL(Bundle.module.bundleURL))
  public static let symbol = "keyboard"
  public static let kind = FeatureKind.utility
  public static let summary = LocalizedStringResource("Lock every key while you wipe the keyboard", bundle: .atURL(Bundle.module.bundleURL))
  public static let details = LocalizedStringResource("Every key on your Mac stops working while you clean: letters, Esc, the function row, brightness and sound. The keyboard is drawn on the screen, and each key you wipe looks cleaner. One click turns it back on.", bundle: .atURL(Bundle.module.bundleURL))
  public static let author = "@OrtexIsArtem"
  public static let isRecommended = true
  /// The files in Resources/Catalog/, which the build copies to the top of the bundle, without the folder.
  public static let preview: FeaturePreview? = FeaturePreview(
    video: Bundle.module.url(forResource: "preview", withExtension: "mov"),
    still: Bundle.module.url(forResource: "still", withExtension: "jpg")
  )
  public static let permissionNeeds = [
    PermissionNeed(
      .accessibility,
      reason: LocalizedStringResource("Locks the keyboard while you clean it.", bundle: .atURL(Bundle.module.bundleURL))
    ),
  ]

  /// One store for the life of the app: the lock outlives any view.
  static let store = Store(initialState: KeyboardCleaningFeature.State()) {
    KeyboardCleaningFeature()
  }

  /// Locking the keyboard. Its lock screen covers the window, so the shell opens the window first; its shortcut, which
  /// the shell records on its settings page, runs it the same way.
  public static func makeUtilityActions() -> [UtilityAction] {
    [
      UtilityAction(
        id: "\(id).lock",
        feature: id,
        symbol: symbol,
        label: LocalizedStringResource("Lock Keyboard", bundle: .atURL(Bundle.module.bundleURL)),
        help: LocalizedStringResource("Lock the keyboard for cleaning", bundle: .atURL(Bundle.module.bundleURL)),
        window: .open,
        permission: .accessibility,
        shortcut: Hotkey.lockKeyboard.name
      ) {
        store.send(.startTapped)
      },
    ]
  }

  /// The lock screen, over the window while the keys are locked.
  public static func makeWindowCover() -> AnyView? {
    AnyView(KeyboardCleaningView(store: store))
  }

  public static func makeSettings() -> AnyView? {
    AnyView(KeyboardCleaningSettingsView(store: store))
  }

  public static func setEnabled(_ isEnabled: Bool) {
    #if DEBUG
      // A QA run takes commands only on its own channel (VortexPlatform's `QA`): KeyboardCleaningQA.swift.
      registerQACommands()
    #endif
    // Nothing runs in the background; a lock under way ends as the utility stops.
    if !isEnabled { store.send(.stopped) }
  }
}
