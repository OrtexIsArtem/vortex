import SwiftUI
import VortexCore

/// Home, variant B «Вуха»: a widget in the row next to the notch, the middle, and a dock at the bottom.
struct HomeView: View {
  @Environment(\.homeWidgets) private var widgets

  var body: some View {
    let layout = HomeLayout(widgets)
    VStack(spacing: 0) {
      Group {
        if let header = layout.header {
          header.view
        } else {
          Text("Home", bundle: .module)
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: VortexMetrics.headerHeight)

      if layout.main.isEmpty && layout.dock.isEmpty {
        EmptyHome()
      } else {
        if !layout.main.isEmpty {
          VStack(alignment: .leading, spacing: 18) {
            ForEach(layout.main) { $0.view }
          }
          .padding(.top, 8)
          .padding(.leading, 10)
          .padding(.trailing, 18)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        if !layout.dock.isEmpty {
          Dock(widgets: layout.dock)
            .frame(maxHeight: layout.dockHeight ?? .infinity)
            .frame(height: layout.dockHeight)
            .padding(.top, layout.main.isEmpty ? 4 : 0)
        }
      }
    }
  }
}

/// The panel at the bottom: widgets side by side, hairlines between them.
private struct Dock: View {
  let widgets: [HomeWidget]

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      ForEach(Array(widgets.enumerated()), id: \.element.id) { index, widget in
        if index > 0 {
          Rectangle()
            .fill(VortexColor.line)
            .frame(width: 1)
        }
        widget.view
      }
    }
    .padding(.vertical, 14)
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(VortexColor.dock))
    .padding(.leading, 4)
    .padding(.trailing, 12)
    .padding(.bottom, 12)
  }
}

private struct EmptyHome: View {
  var body: some View {
    Text("Widgets of enabled features appear here", bundle: .module)
      .font(.system(size: 12.5))
      .foregroundStyle(VortexColor.tertiaryText)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.bottom, VortexMetrics.headerHeight)
  }
}
