import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// Entry point the app shell reads; registered in Features/Registry.
@MainActor
public enum TimerModule: FeatureModule {
  public static let id: FeatureID = TimerFeature.id
  public static let title = LocalizedStringResource("Timer", bundle: .atURL(Bundle.module.bundleURL))
  public static let symbol = "timer"
  public static let summary = LocalizedStringResource("One timer at a time, counting down in the notch", bundle: .atURL(Bundle.module.bundleURL))
  public static let details = LocalizedStringResource("Set the minutes on the drum. The countdown sits in the notch, and when time is up you get a sound, a notification and a flash until you see it.", bundle: .atURL(Bundle.module.bundleURL))
  public static let author = "@OrtexIsArtem"
  public static let isRecommended = true
  public static let keeps: LocalizedStringResource? = LocalizedStringResource("The running timer and its settings.", bundle: .atURL(Bundle.module.bundleURL))
  public static let dataFolder: String? = "Timer"
  public static let permissionNeeds = [
    PermissionNeed(
      .notifications,
      reason: LocalizedStringResource("Tells you when a timer ends.", bundle: .atURL(Bundle.module.bundleURL))
    ),
  ]

  /// One store for the life of the app: a run goes on while the window is closed.
  static let store = Store(initialState: TimerFeature.State()) {
    TimerFeature()
  }

  public static func makeTab() -> AnyView {
    AnyView(TimerView(store: store))
  }

  public static func makeSettings() -> AnyView? {
    AnyView(TimerSettingsView(store: store))
  }

  public static func makeHomeWidgets() -> [HomeWidget] {
    [HomeWidget(id: "timer.timer", feature: id, title: title, place: .notchRow, view: TimerHomeWidget(store: store))]
  }

  public static func setEnabled(_ isEnabled: Bool) {
    #if DEBUG
      registerQACommands()
    #endif
    store.send(isEnabled ? .start : .stop)
  }

  #if DEBUG
    private static var isRegistered = false

    /// QA mode: `timer press=turnOn|restart` presses the Notifications row in the settings.
    private static func registerQACommands() {
      guard QA.isActive, !isRegistered else { return }
      isRegistered = true
      QA.register(command: "timer") { arguments in
        let pressed = try QAPermissions.pressRow(
          arguments,
          needs: permissionNeeds,
          statuses: store.permissionStatuses,
          turnOn: { store.send(.turnOnTapped($0)) },
          restart: { store.send(.restartTapped) }
        )
        guard pressed else { throw QAError("timer takes press=turnOn or press=restart") }
      }
    }
  #endif
}
