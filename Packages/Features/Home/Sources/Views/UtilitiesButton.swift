import SwiftUI
import VortexCore

/// Home's utilities button, in its slot at the right end of the notch row or wherever the editor put it: the utilities,
/// whose strip comes out at the window's right, or the pencil, Edit Home itself, while the dock offers nothing. What a
/// click on the utilities does is the shell's.
struct UtilitiesButton: View {
  /// Its slot at the row's right end, as wide as its target: the 28 pt circle in the middle, 8 pt from the window's edge.
  static let slot = VortexMetrics.hitTarget

  /// What the button is.
  enum Mode: Equatable {
    case utilities
    case pencil

    /// The pencil while the dock has no button, as without the shell.
    init(_ dock: UtilitiesDock?) {
      self = (dock?.buttons.isEmpty ?? true) ? .pencil : .utilities
    }
  }

  let dock: UtilitiesDock?
  /// Out of its slot, over the row and the widgets.
  var isFloating = false
  let edit: @MainActor () -> Void

  var body: some View {
    switch Mode(dock) {
    case .pencil:
      RoundButton(symbol: "pencil", label: Text("Edit Home", bundle: .module), isFloating: isFloating, action: edit)
    case .utilities:
      if let dock {
        // A permission one of them needs is off: the yellow dot of the first, as the strip marks its button.
        let warning = dock.buttons.lazy.compactMap(\.warning).first
        RoundButton(
          symbol: "wrench.and.screwdriver",
          label: Text("Utilities", bundle: .module),
          isSelected: dock.isOpen,
          isFloating: isFloating,
          action: dock.toggle
        ) {
          if let warning {
            WarningMark(warning, style: .dot, size: 7).offset(x: 1, y: -1)
          }
        }
      }
    }
  }
}

/// The dock's strip at the window's right: its buttons in one column, the first beside the utilities button, then, set
/// apart, the pencil, which is Home's own and no utility. Each button puts the strip away as it runs.
struct UtilitiesStrip: View {
  let dock: UtilitiesDock
  /// The utilities button's middle, from the window's top.
  let buttonY: CGFloat
  let edit: @MainActor () -> Void

  var body: some View {
    VStack(spacing: 0) {
      ForEach(dock.buttons) { button in
        RoundButton(
          symbol: button.symbol,
          label: Text(button.label),
          help: Self.help(button),
          action: { dock.run(button.id) }
        ) {
          if let warning = button.warning {
            WarningMark(warning, size: 9).offset(x: 3, y: -2)
          }
        }
        .accessibilityValue(button.warning.map { Text($0.offLabel) } ?? Text(verbatim: ""))
      }
      Rectangle()
        .fill(VortexColor.line)
        .frame(width: 20, height: 1)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
      RoundButton(symbol: "pencil", label: Text("Edit Home", bundle: .module), action: edit)
    }
    .padding(.top, Self.top(buttonY: buttonY, buttons: dock.buttons.count))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(VortexColor.panel)
    .overlay(alignment: .leading) {
      Rectangle().fill(VortexColor.line).frame(width: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text("Utilities", bundle: .module))
  }

  /// The column's top: its first button's middle at the utilities button's, `buttonY`, moved up only as far as the
  /// column, its buttons, the 13 pt line and the pencil, needs to stay inside the window.
  static func top(buttonY: CGFloat, buttons: Int) -> CGFloat {
    let height = CGFloat(buttons + 1) * VortexMetrics.hitTarget + 13
    return min(buttonY - VortexMetrics.hitTarget / 2, WindowSize.regular.size.height - height)
  }

  /// "Copy Text (⌃⌥T)", and on a second line the permission that is off.
  static func help(_ button: UtilitiesDockButton) -> Text {
    var text = Text(button.label)
    if let keys = button.keys { text = text + Text(verbatim: " (\(keys))") }
    if let warning = button.warning { text = text + Text(verbatim: "\n") + Text(warning.offLabel) }
    return text
  }
}

/// A round button of the quiet style, a quarter smaller than the capsule's were: a 28 pt circle, lit while the pointer
/// is over it or while what it opens is out, in a 44 pt target.
struct RoundButton<Badge: View>: View {
  let symbol: String
  let label: Text
  /// The tooltip, when it says more than the label.
  var help: Text?
  var isSelected = false
  /// Over other content: a soft shadow sets it off, as the app's floating toasts have.
  var isFloating = false
  let action: @MainActor () -> Void
  @ViewBuilder var badge: Badge
  @State private var isHovered = false

  var body: some View {
    let isLit = isHovered || isSelected
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(isLit ? VortexColor.primaryText : VortexColor.secondaryText)
        .frame(width: 28, height: 28)
        .background(
          Circle()
            .fill(isLit ? VortexColor.track : VortexColor.raised)
            .shadow(color: .black.opacity(isFloating ? 0.25 : 0), radius: 12, y: 4)
        )
        .overlay(alignment: .topTrailing) { badge }
        .frame(width: VortexMetrics.hitTarget, height: VortexMetrics.hitTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help(help ?? label)
    .accessibilityLabel(label)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

extension RoundButton where Badge == EmptyView {
  init(
    symbol: String,
    label: Text,
    help: Text? = nil,
    isSelected: Bool = false,
    isFloating: Bool = false,
    action: @escaping @MainActor () -> Void
  ) {
    self.init(
      symbol: symbol, label: label, help: help, isSelected: isSelected, isFloating: isFloating, action: action
    ) { EmptyView() }
  }
}
