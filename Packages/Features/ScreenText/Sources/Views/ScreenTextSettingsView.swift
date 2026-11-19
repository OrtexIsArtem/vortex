import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// Screen Text's page in Settings › Features: its shortcut, and a row while Screen Recording isn't working.
struct ScreenTextSettingsView: View {
  let store: StoreOf<ScreenTextFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsRow(
        title: Text("Copy text from the screen", bundle: .module),
        caption: Text("Freezes the screen: the text in the frame you draw goes to the clipboard.", bundle: .module)
      ) {
        HotkeyRecorder(.copyScreenText, label: Text("Copy text from the screen", bundle: .module))
      }

      PermissionRows(
        ScreenTextModule.permissionNeeds,
        statuses: store.permissionStatuses,
        turnOn: { store.send(.turnOnTapped($0)) },
        restart: { store.send(.restartTapped) }
      )

      Text("Text and QR codes are read on this Mac. Vortex keeps none of it.", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
        .padding(.top, 12)
    }
    .onAppear { store.send(.settingsShown) }
  }
}
