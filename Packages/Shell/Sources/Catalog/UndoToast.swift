import ComposableArchitecture
import SwiftUI
import VortexCore

/// "<Feature> removed · Undo", for 5 s after a feature is removed.
struct UndoToast: View {
  let store: StoreOf<ShellFeature>
  let feature: FeatureDescriptor

  var body: some View {
    HStack(spacing: 10) {
      Text("\(Text(feature.title)) removed", bundle: .module)
        .foregroundStyle(VortexColor.secondaryText)
      Button {
        store.send(.undoRemoveTapped)
      } label: {
        Text("Undo", bundle: .module)
          .fontWeight(.semibold)
          .foregroundStyle(VortexColor.primaryText)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .font(.system(size: 12.5))
    .padding(.horizontal, 16)
    .frame(height: 36)
    .background(Capsule().fill(VortexColor.raised))
    .overlay(Capsule().strokeBorder(VortexColor.line))
  }
}
