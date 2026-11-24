import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// Entry point the app shell reads; registered in Features/Registry. A utility, without a tab: its whole look is the
/// frame on the frozen screen, the notch's message and its settings.
@MainActor
public enum ScreenTextModule: UtilityModule {
  public static let id: FeatureID = ScreenTextFeature.id
  public static let title = LocalizedStringResource("Screen Text", bundle: .atURL(Bundle.module.bundleURL))
  public static let symbol = "text.viewfinder"
  public static let summary = LocalizedStringResource("Copy text you can't select, right off the screen", bundle: .atURL(Bundle.module.bundleURL))
  public static let details = LocalizedStringResource("Start it from your utilities on Home or a shortcut you set, then frame the text on the frozen screen: a screenshot in a chat, a video frame, an error. It's copied at once, a QR code as its link or text. Read on this Mac, in English, Ukrainian and Russian.", bundle: .atURL(Bundle.module.bundleURL))
  public static let author = "@OrtexIsArtem"
  public static let isRecommended = true
  /// The files in Resources/Catalog/, which the build copies to the top of the bundle, without the folder.
  public static let preview: FeaturePreview? = FeaturePreview(
    video: Bundle.module.url(forResource: "preview", withExtension: "mov"),
    still: Bundle.module.url(forResource: "still", withExtension: "jpg")
  )
  public static let permissionNeeds = [
    PermissionNeed(
      .screenRecording,
      reason: LocalizedStringResource("Reads the text in a frame you draw on the screen.", bundle: .atURL(Bundle.module.bundleURL))
    ),
  ]

  /// One store for the life of the app: the shortcut works while the window is closed.
  static let store = Store(initialState: ScreenTextFeature.State()) {
    ScreenTextFeature()
  }

  private static var overlay: ScreenTextOverlay?

  public static func makeSettings() -> AnyView? {
    AnyView(ScreenTextSettingsView(store: store))
  }

  /// Freezing the screen to copy the text in a frame. It works on the screen, so the shell closes its window first; its
  /// shortcut, recorded on the settings page, runs it the same way.
  public static func makeUtilityActions() -> [UtilityAction] {
    [
      UtilityAction(
        id: "\(id).copy",
        feature: id,
        symbol: symbol,
        label: LocalizedStringResource("Copy Text", bundle: .atURL(Bundle.module.bundleURL)),
        help: LocalizedStringResource("Copy text from the screen", bundle: .atURL(Bundle.module.bundleURL)),
        window: .closed,
        permission: .screenRecording,
        shortcut: Hotkey.copyScreenText.name
      ) {
        store.send(.captureRequested)
      },
    ]
  }

  public static func setEnabled(_ isEnabled: Bool) {
    if overlay == nil {
      overlay = ScreenTextOverlay(store: store)
      #if DEBUG
        // A QA run takes commands only on its own channel (VortexPlatform's `QA`): ScreenTextQA.swift.
        registerQACommands(overlay: overlay)
      #endif
    }
    store.send(isEnabled ? .start : .stop)
  }
}
