import ComposableArchitecture
import SwiftUI
import VortexCore

/// Erase Data's question, a layer over the window rather than a sheet: what goes, that it can't be undone, and that
/// Vortex restarts to erase it before any feature starts.
struct EraseConfirmation: View {
  let store: StoreOf<ShellFeature>
  let feature: FeatureDescriptor

  var body: some View {
    ZStack {
      // Takes every click outside the question, which only Cancel and Esc answer otherwise.
      VortexColor.windowBackground.opacity(0.72)
        .contentShape(Rectangle())
        .onTapGesture {}
      VStack(alignment: .leading, spacing: 8) {
        Text("Erase \(Text(feature.title)) data?", bundle: .module)
          .font(.system(size: 13, weight: .semibold))
        if let keeps = feature.keeps {
          Text(keeps)
        }
        if let note = feature.eraseNote {
          Text(note)
        }
        Text("This can't be undone. Vortex restarts and erases it before any feature starts.", bundle: .module)
        HStack(spacing: 8) {
          Spacer()
          Button {
            store.send(.eraseCancelled)
          } label: {
            Text("Cancel", bundle: .module)
          }
          .buttonStyle(.quietCapsule)
          Button {
            store.send(.eraseConfirmed)
          } label: {
            Text("Erase and Restart", bundle: .module)
          }
          .buttonStyle(.primaryCapsule)
        }
        .padding(.top, 10)
      }
      .font(.system(size: 12.5))
      .foregroundStyle(VortexColor.primaryText)
      .fixedSize(horizontal: false, vertical: true)
      .padding(20)
      .frame(width: 360)
      .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VortexColor.raised))
      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(VortexColor.line))
      .accessibilityElement(children: .contain)
      .accessibilityAddTraits(.isModal)
    }
  }
}
