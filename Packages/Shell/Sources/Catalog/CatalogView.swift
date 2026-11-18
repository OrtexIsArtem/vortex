import ComposableArchitecture
import SwiftUI
import VortexCore

/// The catalog: every feature Vortex ships, added or not, in the large window.
struct CatalogView: View {
  let store: StoreOf<ShellFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Features", bundle: .module)
        .font(.system(size: 13, weight: .semibold))
        .frame(height: VortexMetrics.headerHeight)
        .padding(.leading, 10)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
