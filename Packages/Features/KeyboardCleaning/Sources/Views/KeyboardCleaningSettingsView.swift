import ComposableArchitecture
import SwiftUI
import VortexCore

/// Keyboard cleaning's own settings in Settings › Features, under the shortcut of its utility action, which the shell
/// shows first: a row while Accessibility isn't working.
struct KeyboardCleaningSettingsView: View {
  let store: StoreOf<KeyboardCleaningFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      PermissionRows(
        KeyboardCleaningModule.permissionNeeds,
        statuses: store.statuses,
        turnOn: { store.send(.turnOnTapped($0)) },
        restart: { store.send(.restartTapped) }
      )

      Text("While the keys are locked, Vortex reads only which key goes down, to draw it cleaner, and keeps none of it.", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 12)
    }
    .onAppear { store.send(.settingsShown) }
  }
}
