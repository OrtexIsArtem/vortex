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
    #if DEBUG
      registerQACommands()
    #endif
    store.send(isEnabled ? .start : .stop)
  }

  #if DEBUG
    private static var isRegistered = false

    /// QA mode: `clipboard press=turnOn|restart` presses the Paste from Other Apps row in the settings.
    private static func registerQACommands() {
      guard QA.isActive, !isRegistered else { return }
      isRegistered = true
      QA.register(command: "clipboard") { arguments in
        let pressed = try QAPermissions.pressRow(
          arguments,
          needs: permissionNeeds,
          statuses: store.permissionStatuses,
          turnOn: { store.send(.turnOnTapped($0)) },
          restart: { store.send(.restartTapped) }
        )
        guard pressed else { throw QAError("clipboard takes press=turnOn or press=restart") }
      }
    }
  #endif
}
