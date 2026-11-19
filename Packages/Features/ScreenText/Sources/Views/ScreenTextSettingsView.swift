import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// Screen Text's own settings in Settings › Features, under the shortcut of its utility action, which the shell shows
/// first: a row while Screen Recording isn't working, and what it keeps.
struct ScreenTextSettingsView: View {
  let store: StoreOf<ScreenTextFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
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
