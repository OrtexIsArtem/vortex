import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// Safe mode's explanation, over Home: Vortex quit right after it started and nobody can be blamed, so the features
/// wait for the user.
struct SafeModeBanner: View {
  let store: StoreOf<ShellFeature>

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: "info.circle")
        .font(.system(size: 16))
        .foregroundStyle(VortexColor.secondaryText)
        .accessibilityHidden(true)
      Text("Vortex quit right after it started, so features are paused for this launch.", bundle: .module)
        .font(.system(size: 12))
        .foregroundStyle(VortexColor.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        store.send(.startAllTapped)
      } label: {
        Text("Start All", bundle: .module)
      }
      .buttonStyle(.primaryCapsule)
      .fixedSize()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(VortexColor.raised))
    .accessibilityElement(children: .contain)
  }
}
