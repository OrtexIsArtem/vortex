import ComposableArchitecture
import SwiftUI
import VortexCore

/// What the window shows instead of the sidebar and the tab while the keys are locked for cleaning, centered.
struct KeyboardCleaningView: View {
  let store: StoreOf<KeyboardCleaningFeature>

  var body: some View {
    VStack(spacing: 0) {
      Image(systemName: "keyboard")
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(VortexColor.secondaryText)
        .accessibilityHidden(true)
      Text("Keyboard cleaning mode", bundle: .module)
        .font(.system(size: 17, weight: .semibold))
        .padding(.top, 18)
      Text("All keys are locked", bundle: .module)
        .font(.system(size: 13))
        .foregroundStyle(VortexColor.secondaryText)
        .padding(.top, 6)
      Button {
        store.send(.stopTapped)
      } label: {
        Text("Turn the keyboard back on", bundle: .module)
      }
      .buttonStyle(PrimaryCapsuleButtonStyle(height: 44, fontSize: 14))
      .padding(.top, 26)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(VortexColor.windowBackground)
  }
}
