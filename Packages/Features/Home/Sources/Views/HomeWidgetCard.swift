import SwiftUI
import VortexCore

/// A widget on the grid: its card at its cells, the widget laid out inside at its size.
struct HomeWidgetCard: View {
  let widget: HomeWidget
  let placement: Placement
  let isEditing: Bool
  let remove: () -> Void

  var body: some View {
    let frame = HomeGrid.frame(column: placement.column, row: placement.row, size: placement.size)
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    widget.view
      .environment(\.homeWidgetSize, placement.size)
      .padding(.vertical, 14)
      .padding(.horizontal, 16)
      .frame(width: frame.width, height: frame.height, alignment: .topLeading)
      .background(shape.fill(VortexColor.dock))
      .clipShape(shape)
      .modifier(EditorChrome(isEditing: isEditing, cornerRadius: 18, inset: 0, widget: widget, remove: remove))
      .offset(x: frame.minX, y: frame.minY)
  }
}

/// In the editor a widget doesn't answer the pointer. Under the pointer, or with the keyboard's focus (Tab), it shows a
/// 1 pt ring and "−" at its top left corner; Delete removes it too.
struct EditorChrome: ViewModifier {
  let isEditing: Bool
  let cornerRadius: CGFloat
  /// How far inside the widget's edges the ring is drawn.
  let inset: CGFloat
  let widget: HomeWidget
  let remove: () -> Void
  @State private var isHovered = false
  @FocusState private var isFocused: Bool

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    let showsChrome = isEditing && (isHovered || isFocused)
    content
      .allowsHitTesting(!isEditing)
      .accessibilityHidden(isEditing)
      .overlay {
        if isEditing {
          // Takes the pointer, and VoiceOver, instead of the widget.
          Color.clear
            .contentShape(shape)
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: "\(String(localized: widget.featureTitle)), \(String(localized: widget.title))"))
            .accessibilityAction(named: Text("Remove from Home", bundle: .module), remove)
        }
      }
      .overlay {
        if showsChrome {
          shape.fill(VortexColor.primaryText.opacity(0.02))
            .overlay(shape.strokeBorder(VortexColor.primaryText.opacity(0.28), lineWidth: 1))
            .padding(inset)
            .allowsHitTesting(false)
        }
      }
      .overlay(alignment: .topLeading) {
        if showsChrome {
          // The circle 8 pt out of the corner, its 44 pt target around it.
          RemoveButton(action: remove).offset(x: inset - 20, y: inset - 20)
        }
      }
      // After the "−", so reaching for it keeps the widget under the pointer.
      .onHover { isHovered = $0 }
      .focusable(isEditing)
      .focused($isFocused)
      .focusEffectDisabled()
      .onKeyPress(keys: [.delete, .deleteForward]) { _ in
        guard isEditing else { return .ignored }
        remove()
        return .handled
      }
  }
}

/// The widget's "−" in the editor.
private struct RemoveButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "minus")
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(VortexColor.windowBackground)
        .frame(width: 20, height: 20)
        .background(Circle().fill(VortexColor.tertiaryText))
        .frame(width: VortexMetrics.hitTarget, height: VortexMetrics.hitTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(Text("Remove from Home", bundle: .module))
    .accessibilityLabel(Text("Remove from Home", bundle: .module))
  }
}
