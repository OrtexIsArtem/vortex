import ComposableArchitecture
import SwiftUI
import VortexCore

/// Home: a widget in the row next to the notch, and the others as cards on the 4×2 grid under it. In the editor Home
/// stays where it is, and the window grows to the right for the panel of widgets.
struct HomeView: View {
  let store: StoreOf<HomeFeature>
  @Environment(\.homeWidgets) private var widgets
  @Environment(\.keyboardCleaning) private var keyboardCleaning
  @Environment(\.isWindowOpen) private var isWindowOpen
  @Environment(\.windowRequest) private var windowRequest
  @Environment(\.showCatalog) private var showCatalog

  /// The grid fills the regular window's tab; the panel takes what the large window adds.
  static let gridWidth = HomeGrid.frame(column: 0, row: 0, size: .full).maxX + HomeGrid.sideInset
  static let panelWidth = WindowSize.large.size.width - WindowSize.regular.size.width
  /// What the editor asks of the window: the large one, with the focus.
  static let editorWindow = WindowRequest(size: .large, isFocused: true)

  var body: some View {
    let byID = Dictionary(widgets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        NotchRow(store: store, widget: store.notchRowWidget.flatMap { byID[$0] }, byID: byID)
        GridArea(store: store, byID: byID)
      }
      .frame(width: Self.gridWidth)
      .contextMenu {
        if !store.isEditing {
          Button {
            store.send(.editTapped)
          } label: {
            Text("Edit Home", bundle: .module)
          }
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if !store.isEditing {
          CornerButtons(keyboardCleaning: keyboardCleaning) { store.send(.editTapped) }
            .padding(12)
        }
      }
      if store.isEditing {
        HomeEditorPanel(store: store, byID: byID, showCatalog: showCatalog)
          .frame(width: Self.panelWidth)
      }
    }
    // While the window grows, the panel waits past its right edge.
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onChange(of: store.isEditing) { _, isEditing in
      windowRequest?(isEditing ? Self.editorWindow : .regular)
    }
    .onChange(of: isWindowOpen) { _, isOpen in
      if !isOpen { store.send(.windowClosed) }
    }
    // Left for another tab, as the menu bar menu's Settings does: the editor ends as Cancel ends it, and gives the
    // window back.
    .onDisappear {
      guard store.isEditing else { return }
      store.send(.cancelTapped)
      windowRequest?(.regular)
    }
  }
}

/// The row next to the notch: its widget, or Home's title.
private struct NotchRow: View {
  let store: StoreOf<HomeFeature>
  let widget: HomeWidget?
  let byID: [String: HomeWidget]

  var body: some View {
    Group {
      if widget == nil, case let .notchRow(id) = store.preview, let copy = byID[id] {
        // The copy of a widget from the panel, in the row it would go to.
        copy.view
          .opacity(0.45)
          .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .strokeBorder(VortexColor.secondaryText, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
              .padding(8)
          )
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      } else if let widget {
        widget.view
          // The ring and "−" stay inside the row, clear of the window's top edge.
          .modifier(EditorChrome(isEditing: store.isEditing, cornerRadius: 14, inset: 8, widget: widget) {
            store.send(.removeTapped(widget.id))
          })
      } else {
        Text("Home", bundle: .module)
          .font(.system(size: 13, weight: .semibold))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.leading, 10)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: VortexMetrics.headerHeight)
  }
}

/// The 4×2 grid: the cards of the widgets on Home and, in the editor, the free cells dashed, the copy of a widget from
/// the panel, and where a dragged widget would land, the widgets in its way already moved aside.
private struct GridArea: View {
  let store: StoreOf<HomeFeature>
  let byID: [String: HomeWidget]
  @State private var drag: Drag?

  /// A widget being dragged, and how far.
  struct Drag: Equatable {
    var widget: String
    var offset: CGSize
  }

  var body: some View {
    let visible = store.visible
    if visible.isEmpty, store.notchRowWidget == nil, !store.isEditing {
      EmptyHome { store.send(.editTapped) }
    } else {
      let arranged = arrangement(visible)
      ZStack(alignment: .topLeading) {
        if store.isEditing {
          // The copy's cells aren't free: their outlines would show through it.
          ForEach(Self.freeCells((arranged ?? visible) + [store.preview].compactMap(\.?.placement)), id: \.self) { cell in
            let frame = HomeGrid.frame(column: cell.column, row: cell.row, size: .small)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .strokeBorder(VortexColor.dropOutline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
              .frame(width: frame.width, height: frame.height)
              .offset(x: frame.minX, y: frame.minY)
              .accessibilityHidden(true)
          }
          if case let .at(placement) = store.preview, let widget = byID[placement.widget] {
            let frame = HomeGrid.frame(column: placement.column, row: placement.row, size: placement.size)
            WidgetCopy(widget: widget, size: placement.size)
              .offset(x: frame.minX, y: frame.minY)
          }
          if let landing = arranged?.first(where: { $0.widget == drag?.widget }) {
            let frame = HomeGrid.frame(column: landing.column, row: landing.row, size: landing.size)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .strokeBorder(VortexColor.secondaryText, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
              .frame(width: frame.width, height: frame.height)
              .offset(x: frame.minX, y: frame.minY)
              .accessibilityHidden(true)
          }
        }
        ForEach(visible, id: \.widget) { placement in
          if let widget = byID[placement.widget] {
            let isDragged = drag?.widget == placement.widget
            // The others show where the drop would put them, and slide there.
            let shown = isDragged ? placement : arranged?.first(where: { $0.widget == placement.widget }) ?? placement
            HomeWidgetCard(
              widget: widget,
              placement: shown,
              isEditing: store.isEditing,
              dragOffset: isDragged ? drag?.offset ?? .zero : .zero,
              onDrag: { drag = Drag(widget: placement.widget, offset: $0) },
              onDrop: { offset in
                // Where the grid showed it landing, the widgets in its way moved aside; or back, and nothing moves.
                let cell = placement.cell(movedBy: drag?.offset ?? offset)
                withAnimation(.snappy(duration: 0.25)) {
                  store.send(.dropped(placement.widget, column: cell.column, row: cell.row))
                  drag = nil
                }
              },
              remove: { store.send(.removeTapped(placement.widget)) }
            )
            .animation(.snappy(duration: 0.25), value: shown)
            .zIndex(isDragged ? 1 : 0)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      // Done or the window closing mid-drag: nothing stays lifted.
      .onChange(of: store.isEditing) { drag = nil }
    }
  }

  /// While a widget is dragged, the widgets on the grid as dropping it now would leave them: it where its top left corner
  /// is nearest, the widgets in its way moved aside. Nil where it would go back.
  private func arrangement(_ visible: [Placement]) -> [Placement]? {
    guard let drag, let placement = visible.first(where: { $0.widget == drag.widget }) else { return nil }
    let cell = placement.cell(movedBy: drag.offset)
    return store.state.layout(moving: drag.widget, column: cell.column, row: cell.row)?.visible(store.available)
  }

  /// The cells no widget covers.
  static func freeCells(_ visible: [Placement]) -> [GridCell] {
    let layout = HomeLayout(notchRow: nil, placed: visible)
    return (0..<HomeGrid.rows).flatMap { row in
      (0..<HomeGrid.columns).compactMap { column in
        layout.fits(.small, column: column, row: row, ignoring: []) ? GridCell(column: column, row: row) : nil
      }
    }
  }
}

/// The capsule in Home's bottom right corner: keyboard cleaning, when the shell offers it, and the pencil that turns
/// Home into the editor.
private struct CornerButtons: View {
  let keyboardCleaning: (@MainActor () -> Void)?
  let edit: () -> Void

  var body: some View {
    HStack(spacing: 2) {
      if let keyboardCleaning {
        KeyboardCleaningButton(action: keyboardCleaning)
      }
      CornerButton(symbol: "pencil", label: Text("Edit Home", bundle: .module), action: edit)
    }
    .padding(.horizontal, 2)
    .frame(height: 40)
    .background(Capsule().fill(VortexColor.raised))
    // A 1 pt ring just outside the capsule.
    .background(Capsule().fill(VortexColor.primaryText.opacity(0.07)).padding(-1))
  }
}

/// A round button in the corner capsule, which lights up under the pointer.
private struct CornerButton<Badge: View>: View {
  let symbol: String
  let label: Text
  /// The tooltip, when it says more than the label.
  var help: Text?
  let action: () -> Void
  @ViewBuilder var badge: Badge
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 14))
        .foregroundStyle(isHovered ? VortexColor.primaryText : VortexColor.secondaryText)
        .frame(width: 36, height: 36)
        .background(Circle().fill(isHovered ? VortexColor.track : .clear))
        .overlay(alignment: .topTrailing) { badge }
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help(help ?? label)
    .accessibilityLabel(label)
  }
}

extension CornerButton where Badge == EmptyView {
  init(symbol: String, label: Text, action: @escaping () -> Void) {
    self.init(symbol: symbol, label: label, help: nil, action: action) { EmptyView() }
  }
}

/// Keyboard cleaning's button: what a click does is the shell's. Accessibility off: a yellow warning on it.
private struct KeyboardCleaningButton: View {
  let action: @MainActor () -> Void
  @SharedReader(.permissionStatuses) private var permissionStatuses

  var body: some View {
    let showsWarning = PermissionMark(permissionStatuses[.accessibility]) == .warning
    CornerButton(
      symbol: "keyboard",
      label: Text("Lock the keyboard for cleaning", bundle: .module),
      help: showsWarning ? Text(Permission.accessibility.offLabel) : nil,
      action: action
    ) {
      if showsWarning {
        WarningMark(.accessibility, size: 9).offset(x: -4, y: 4)
      }
    }
    .accessibilityValue(showsWarning ? Text(Permission.accessibility.offLabel) : Text(verbatim: ""))
  }
}

/// Nothing on Home: widgets go there only from the editor, so it says so and opens it.
private struct EmptyHome: View {
  let edit: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Text("No widgets on Home", bundle: .module)
        .font(.system(size: 12.5))
        .foregroundStyle(VortexColor.tertiaryText)
      Button(action: edit) {
        Text("Edit Home", bundle: .module)
      }
      .buttonStyle(.quietCapsule)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.bottom, VortexMetrics.headerHeight)
  }
}
