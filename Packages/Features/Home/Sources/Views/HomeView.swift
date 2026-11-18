import ComposableArchitecture
import SwiftUI
import VortexCore

/// Home: a widget in the row next to the notch, and the others as cards on the 4×2 grid under it.
struct HomeView: View {
  let store: StoreOf<HomeFeature>
  @Environment(\.homeWidgets) private var widgets
  @Environment(\.keyboardCleaning) private var keyboardCleaning

  var body: some View {
    let infos = widgets.map(WidgetInfo.init)
    let byID = Dictionary(widgets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let visible = store.visible
    VStack(spacing: 0) {
      Group {
        if let id = store.notchRowWidget, let widget = byID[id] {
          widget.view
        } else {
          Text("Home", bundle: .module)
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 10)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: VortexMetrics.headerHeight)

      if visible.isEmpty, store.notchRowWidget == nil {
        EmptyHome()
      } else {
        ZStack(alignment: .topLeading) {
          ForEach(visible, id: \.widget) { placement in
            if let widget = byID[placement.widget] {
              WidgetCard(widget: widget, placement: placement)
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
    .overlay(alignment: .bottomTrailing) {
      if let keyboardCleaning {
        KeyboardCleaningButton(action: keyboardCleaning).padding(12)
      }
    }
    // The running features' widgets, whenever they change: Home lays them out and keeps where they are.
    .onChange(of: infos, initial: true) { _, infos in
      store.send(.widgetsChanged(infos))
    }
  }
}

/// A widget on the grid: its card at its cells, the widget laid out inside at its size.
private struct WidgetCard: View {
  let widget: HomeWidget
  let placement: Placement

  var body: some View {
    let frame = HomeGrid.frame(column: placement.column, row: placement.row, size: placement.size)
    widget.view
      .environment(\.homeWidgetSize, placement.size)
      .padding(.vertical, 14)
      .padding(.horizontal, 16)
      .frame(width: frame.width, height: frame.height, alignment: .topLeading)
      .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(VortexColor.dock))
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .offset(x: frame.minX, y: frame.minY)
  }
}

extension WidgetInfo {
  /// The widget without its view, its names in the app's language.
  init(_ widget: HomeWidget) {
    self.init(
      id: widget.id,
      feature: widget.feature,
      place: widget.place,
      name: String(localized: widget.title),
      featureName: String(localized: widget.featureTitle),
      featureSymbol: widget.featureSymbol
    )
  }
}

/// A quiet keyboard in Home's bottom right corner, which lights up under the pointer.
private struct KeyboardCleaningButton: View {
  let action: @MainActor () -> Void
  @State private var isHovered = false
  /// Accessibility off: a yellow warning on the button; what a click does is the shell's.
  @SharedReader(.permissionStatuses) private var permissionStatuses

  var body: some View {
    let showsWarning = PermissionMark(permissionStatuses[.accessibility]) == .warning
    Button(action: action) {
      Image(systemName: "keyboard")
        .font(.system(size: 13))
        .foregroundStyle(isHovered ? VortexColor.primaryText : VortexColor.tertiaryText)
        .frame(width: 30, height: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isHovered ? VortexColor.track : .clear))
        .overlay(alignment: .topTrailing) {
          if showsWarning {
            WarningMark(.accessibility, size: 9).offset(x: 2, y: -1)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help(showsWarning ? Text(Permission.accessibility.offLabel) : Text("Lock the keyboard for cleaning", bundle: .module))
    .accessibilityLabel(Text("Lock the keyboard for cleaning", bundle: .module))
    .accessibilityValue(showsWarning ? Text(Permission.accessibility.offLabel) : Text(verbatim: ""))
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
