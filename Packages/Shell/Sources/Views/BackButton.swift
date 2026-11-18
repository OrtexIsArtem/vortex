import SwiftUI
import VortexCore

/// "‹ <list>" in a page's header row, back to the list the page belongs to: a feature's page in the catalog, and one in
/// Settings › Features.
struct BackButton: View {
  let title: Text
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 2) {
        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
        title
      }
      .font(.system(size: 12.5))
      .foregroundStyle(VortexColor.secondaryText)
      .padding(.horizontal, 6)
      .frame(height: 28)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .frame(height: VortexMetrics.headerHeight)
    .padding(.leading, 4)
  }
}
