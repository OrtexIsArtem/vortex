import ComposableArchitecture
import SwiftUI
import VortexCore

/// Home: a widget in the row next to the notch, and the others as cards on the 4×2 grid under it; the utilities button
/// floats over them, in its slot at the row's right end unless the editor moved it. In the editor Home stays where it
/// is, and the window grows to the right for the panel of widgets; so it does by a narrow strip for the utilities dock.
/// On a wide notch the window is wider: the row spans it, and the grid keeps its size in the middle, the extra room
/// equal margins at its sides.
struct HomeView: View {
  let store: StoreOf<HomeFeature>
  @Environment(\.homeWidgets) private var widgets
  @Environment(\.utilitiesDock) private var dock
  @Environment(\.isWindowOpen) private var isWindowOpen
  @Environment(\.windowRequest) private var windowRequest
  @Environment(\.showCatalog) private var showCatalog
  @Environment(\.notchCutout) private var cutout

  /// The grid fills the regular window's tab, up to a 186 pt notch; the panel takes what the large window adds, the
  /// dock's strip what its window adds, on every notch.
  static let gridWidth = HomeGrid.frame(column: 0, row: 0, size: .full).maxX + HomeGrid.sideInset
  static let panelWidth = WindowSize.large.size.width - WindowSize.regular.size.width
  static let dockWidth = WindowSize.dock.size.width - WindowSize.regular.size.width

  /// Home's own column, the regular window's tab on a display whose notch is `notchWidth` points wide: the grid's
  /// width, or more on a wide notch (`VortexMetrics.regularWidth(notchWidth:)`), 678 pt on a 240 pt one. The notch row
  /// spans it; the grid stays in its middle.
  nonisolated static func width(notchWidth: CGFloat?) -> CGFloat {
    WindowSize.regular.size(notchWidth: notchWidth).width - VortexMetrics.sidebarWidth
  }
  /// What the editor asks of the window: the large one, with the focus.
  static let editorWindow = WindowRequest(size: .large, isFocused: true)

  var body: some View {
    let byID = Dictionary(widgets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let isDockOpen = !store.isEditing && dock?.isOpen == true
    let width = Self.width(notchWidth: cutout?.width)
    // Where the utilities button's center shows in the layout Home shows: its slot, or its place.
    let button = HomeLayout.buttonCenter(store.layout?.button, notch: cutout)
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        NotchRow(store: store, widget: store.notchRowWidget.flatMap { byID[$0] }, byID: byID)
        GridArea(store: store, byID: byID)
          // On a wide notch the grid keeps its size in the column's middle: the extra room is equal margins.
          .frame(width: Self.gridWidth)
          .frame(maxWidth: .infinity)
      }
      // As wide as the regular window's tab, the panel or the strip past it.
      .frame(width: width)
      .contextMenu {
        if !store.isEditing {
          Button {
            store.send(.editTapped)
          } label: {
            Text("Edit Home", bundle: .module)
          }
        }
      }
      if store.isEditing {
        HomeEditorPanel(store: store, byID: byID, showCatalog: showCatalog)
          .frame(width: Self.panelWidth)
      } else if isDockOpen, let dock {
        UtilitiesStrip(dock: dock, buttonY: button.y) { store.send(.editTapped) }
          .frame(width: Self.dockWidth)
      }
    }
    // Over the row and the grid, and over the editor's panel while a drag takes it there.
    .overlay(alignment: .topLeading) {
      FloatingButton(store: store, dock: dock, center: button)
    }
    .overlay(alignment: .leading) {
      // A click anywhere on Home outside the strip puts it away, the utilities button included. A button, as the first
      // click in a window opened by hover reaches buttons only.
      if isDockOpen, let dock {
        Button {
          dock.close()
        } label: {
          Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
        .frame(width: width)
      }
    }
    // While the window grows, the panel waits past its right edge.
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .onChange(of: cutout, initial: true) { _, cutout in
      store.send(.notchChanged(cutout))
    }
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

/// The row next to the notch: its widget, or Home's title, and at its right end the utilities button's slot after the
/// widget's controls, kept wherever the button is, so the notch stays in the window's middle.
private struct NotchRow: View {
  let store: StoreOf<HomeFeature>
  let widget: HomeWidget?
  let byID: [String: HomeWidget]

  var body: some View {
    HStack(spacing: 0) {
      content
        .frame(maxWidth: .infinity)
      Color.clear
        .frame(width: UtilitiesButton.slot)
    }
    .frame(height: VortexMetrics.headerHeight)
  }

  private var content: some View {
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
  }
}

/// The utilities button at its center over Home: over the row, the grid and a dragged widget. Out of its slot it
/// floats, with a shadow. In the editor it answers no click: the pointer or the keyboard's focus gives it the editor's
/// ring, and a drag moves it alone, the drop settling where the layout's rules put it.
private struct FloatingButton: View {
  let store: StoreOf<HomeFeature>
  let dock: UtilitiesDock?
  /// Where its center shows, from the top left of Home's column.
  let center: CGPoint
  /// How far the pointer has dragged it so far.
  @State private var drag = CGSize.zero
  @State private var isHovered = false
  @FocusState private var isFocused: Bool

  var body: some View {
    let isEditing = store.isEditing
    UtilitiesButton(dock: dock, isFloating: store.layout?.button != nil || drag != .zero) { store.send(.editTapped) }
      .allowsHitTesting(!isEditing)
      .accessibilityHidden(isEditing)
      .overlay {
        if isEditing {
          // Takes the pointer instead of the button.
          Circle()
            .strokeBorder(VortexColor.primaryText.opacity(isHovered || isFocused ? 0.28 : 0), lineWidth: 1)
            .padding((UtilitiesButton.slot - 28) / 2)
            .contentShape(Rectangle())
        }
      }
      .onHover { isHovered = $0 }
      .focusable(isEditing)
      .focused($isFocused)
      .focusEffectDisabled()
      .offset(x: center.x - UtilitiesButton.slot / 2 + drag.width, y: center.y - UtilitiesButton.slot / 2 + drag.height)
      .gesture(
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
          .onChanged { drag = $0.translation }
          .onEnded { value in
            let point = CGPoint(x: center.x + value.translation.width, y: center.y + value.translation.height)
            withAnimation(.snappy(duration: 0.25)) {
              store.send(.buttonDropped(point))
              drag = .zero
            }
          },
        including: isEditing ? .all : .subviews
      )
      // Done or the window closing mid-drag: it doesn't stay lifted.
      .onChange(of: isEditing) { drag = .zero }
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
    if let empty = store.emptyGrid {
      EmptyHome(empty: empty) { store.send(.editTapped) }
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

/// Nothing on the grid: widgets go there only from the editor, so it says what is empty, Home or, under a widget in the
/// notch row, the grid, and opens the editor.
private struct EmptyHome: View {
  let empty: HomeFeature.State.EmptyGrid
  let edit: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Group {
        switch empty {
        case .home: Text("No widgets on Home", bundle: .module)
        case .grid: Text("No widgets on Home's grid", bundle: .module)
        }
      }
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
