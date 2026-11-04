import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The guide panel next to System Settings: the permission's title, a smaller illustration, the live checkbox and
/// "Back". It never takes focus and has no close control.
struct GuidePanelView: View {
  let store: StoreOf<OnboardingFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let permission = store.guided {
        Text(permission.title)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(VortexColor.primaryText)
        SettingsIllustration(permission: permission, names: store.settingsNames, compact: true)
          .frame(height: 150)
        HStack(spacing: 8) {
          Text("Turn on", bundle: .module)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(VortexColor.primaryText)
          Spacer()
          PermissionCheckbox(state: store.state.rowState(permission)) { store.send(.turnOnTapped(permission)) }
        }
        HStack {
          Spacer()
          Button {
            store.send(.backTapped)
          } label: {
            Text("Back", bundle: .module)
          }
          .buttonStyle(.quietCapsule)
        }
      }
    }
    .padding(16)
    .frame(width: OnboardingWindowController.panelSize.width, height: OnboardingWindowController.panelSize.height)
    .background(RoundedRectangle(cornerRadius: 16).fill(VortexColor.windowBackground))
    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(VortexColor.line, lineWidth: 1))
  }
}
