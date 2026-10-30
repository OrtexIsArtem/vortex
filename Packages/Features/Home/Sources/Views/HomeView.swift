import ComposableArchitecture
import SwiftUI
import VortexCore

/// Home, variant B «Вуха»: a widget in the row next to the notch, the middle, and a dock at the bottom.
struct HomeView: View {
  @Environment(\.homeWidgets) private var widgets
  @Environment(\.keyboardCleaning) private var keyboardCleaning

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

      if layout.isEmpty {
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
          Dock(widgets: layout.dock, height: layout.dockHeight, keyboardCleaning: keyboardCleaning)
            .padding(.top, layout.main.isEmpty ? 4 : 0)
        }
      }
    }
    .overlay(alignment: .bottomTrailing) {
      // Without a dock the button keeps to its side, at the bottom, where nothing else is.
      if layout.dock.isEmpty, let keyboardCleaning {
        KeyboardCleaningButton(action: keyboardCleaning).padding(12)
      }
    }
  }
}

/// The panel at the bottom: widgets side by side, hairlines between them, and in the top right corner, at the end of
/// the widgets' title row, the button that locks the keyboard for cleaning.
private struct Dock: View {
  let widgets: [HomeWidget]
  /// The height of the rounded panel itself, its margins not counted; nil fills the room that is left.
  let height: CGFloat?
  let keyboardCleaning: (@MainActor () -> Void)?

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
    .frame(height: height)
    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(VortexColor.dock))
    .overlay(alignment: .topTrailing) {
      if let keyboardCleaning {
        KeyboardCleaningButton(action: keyboardCleaning)
          .padding(.top, 8)
          .padding(.trailing, 10)
      }
    }
    .padding(.leading, 4)
    .padding(.trailing, 12)
    .padding(.bottom, 12)
  }
}

/// A quiet keyboard on the dock, which lights up under the pointer.
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
