import ComposableArchitecture
import SwiftUI
import VortexCore

/// Entry point the app shell reads; registered in Features/Registry.
@MainActor
public enum TimerModule: FeatureModule {
  public static let id: FeatureID = TimerFeature.id
  public static let title = LocalizedStringResource("Timer", bundle: .atURL(Bundle.module.bundleURL))
  public static let symbol = "timer"

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

  public static func makeHomeWidget() -> HomeWidget? {
    HomeWidget(id: id, slot: .header, view: TimerHomeWidget(store: store))
  }

  public static func setEnabled(_ isEnabled: Bool) {
    store.send(isEnabled ? .start : .stop)
  }
}
