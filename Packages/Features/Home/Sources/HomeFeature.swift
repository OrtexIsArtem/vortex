import ComposableArchitecture
import Foundation
import VortexCore

extension SharedKey where Self == FileStorageKey<HomeLayout?>.Default {
  /// Where the widgets are on Home: DataFolder/home.json. Nil until Home first had a widget to lay out.
  static var homeLayout: Self {
    Self[.fileStorage(DataFolder.url.appending(path: "home.json")), default: nil]
  }
}

/// Home: the layout of the running features' widgets, saved in home.json.
@Reducer
struct HomeFeature: Sendable {
  @ObservableState
  struct State: Equatable {
    @Shared(.homeLayout) var saved
    /// The widgets the running features offer now, in sidebar order.
    var widgets: [WidgetInfo] = []

    var available: Set<String> { Set(widgets.map(\.id)) }

    /// The widgets on the grid now: those whose feature runs. An away widget's feature doesn't run: once its feature
    /// is back, the widget either shows again or has left the layout.
    var visible: [Placement] {
      (saved?.placed ?? []).filter { available.contains($0.widget) }
    }

    /// The widget in the row next to the notch, while its feature runs.
    var notchRowWidget: String? {
      saved?.notchRow.flatMap { available.contains($0) ? $0 : nil }
    }

    /// The widgets that show on Home now: on the grid or in the row next to the notch.
    var shownWidgets: Set<String> {
      Set(visible.map(\.widget) + [notchRowWidget].compactMap { $0 })
    }

    /// Home is the editor: the window is wider, with the panel of widgets on the right.
    var isEditing = false
    var panel: Panel = .features
    /// The panel's search; empty shows every feature with widgets.
    var search = ""
    /// The copy of the widget under the pointer in the panel: where it would go, or that it fits nowhere.
    var preview: Preview?
    /// The size chosen in the panel for a widget that isn't on Home: the one its copy and Add use.
    var chosenSizes: [String: HomeWidgetSize] = [:]

    /// Where a widget that isn't on Home would go now: to the notch row while it is free, or at its chosen size (its
    /// first one until another is chosen) in the first free place. Nil for a widget on Home or one no feature offers.
    func place(for id: String) -> Preview? {
      guard let widget = widgets.first(where: { $0.id == id }), !shownWidgets.contains(id) else { return nil }
      switch widget.place {
      case .notchRow:
        return notchRowWidget == nil ? .notchRow(id) : .noRoom(id)
      case let .grid(sizes):
        guard let size = chosenSizes[id] ?? sizes.first,
              let fit = HomeLayout(notchRow: nil, placed: visible).firstFit([size], ignoring: [])
        else { return .noRoom(id) }
        return .at(Placement(widget: id, size: fit.size, column: fit.column, row: fit.row))
      }
    }

    /// The features with widgets, in sidebar order: those with a widget on Home, then the others. A search keeps the
    /// features whose name, or one of whose widgets' names, holds it, in any case.
    var panelSections: (onHome: [FeatureID], more: [FeatureID]) {
      let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
      let shown = shownWidgets
      var onHome: [FeatureID] = []
      var more: [FeatureID] = []
      for feature in widgets.map(\.feature) where !onHome.contains(feature) && !more.contains(feature) {
        let own = widgets.filter { $0.feature == feature }
        let matches = query.isEmpty || own.contains {
          $0.featureName.localizedStandardContains(query) || $0.name.localizedStandardContains(query)
        }
        guard matches else { continue }
        if own.contains(where: { shown.contains($0.id) }) {
          onHome.append(feature)
        } else {
          more.append(feature)
        }
      }
      return (onHome, more)
    }
  }

  /// What the editor's panel shows: the features with widgets, or one feature's widgets.
  enum Panel: Equatable, Sendable {
    case features
    case feature(FeatureID)
  }

  /// Where a widget from the panel would go.
  enum Preview: Equatable, Sendable {
    /// On the grid: a copy at its real size shows there.
    case at(Placement)
    /// In the row next to the notch.
    case notchRow(String)
    /// Nowhere: no free place takes its size.
    case noRoom(String)

    var widget: String {
      switch self {
      case let .at(placement): placement.widget
      case let .notchRow(id), let .noRoom(id): id
      }
    }

    /// Where on the grid the copy shows, if it does.
    var placement: Placement? {
      if case let .at(placement) = self { placement } else { nil }
    }
  }

  enum Action: Equatable {
    /// The running features' widgets, sent by Home's view whenever they change.
    case widgetsChanged([WidgetInfo])
    /// The pencil, or "Edit Home" in Home's menu.
    case editTapped
    case doneTapped
    /// The window closed, however it did: the editor ends with it.
    case windowClosed
    /// A widget's "−", or Delete on the focused widget.
    case removeTapped(String)
    case searchChanged(String)
    /// A feature's row in the panel: its widgets.
    case featureTapped(FeatureID)
    case backTapped
    /// The pointer over a widget in the panel, or nil once it leaves.
    case hovered(String?)
    /// A size in a widget's switcher in the panel.
    case sizeTapped(String, HomeWidgetSize)
    case addTapped(String)
    /// A widget on Home dragged so its top left corner is over a cell.
    case dropped(String, column: Int, row: Int)
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .widgetsChanged(widgets):
        state.widgets = widgets
        if let saved = state.saved {
          let reconciled = saved.reconciled(available: Set(widgets.map(\.id)))
          if reconciled != saved { state.$saved.withLock { $0 = reconciled } }
        } else if !widgets.isEmpty {
          // The first layout waits for a widget: before the user chooses features there is none, and an empty layout
          // saved then would leave the chosen ones off as if added later.
          state.$saved.withLock { $0 = HomeLayout.initial(widgets) }
        }
        return .none

      case .editTapped:
        state.isEditing = true
        return .none

      case .doneTapped, .windowClosed:
        // The next edit starts again with the feature list.
        state.isEditing = false
        state.panel = .features
        state.search = ""
        state.preview = nil
        state.chosenSizes = [:]
        return .none

      case let .removeTapped(id):
        guard state.isEditing else { return .none }
        // Edits are saved at once; the other widgets stay where they are.
        state.$saved.withLock { layout in
          layout?.placed.removeAll { $0.widget == id }
          if layout?.notchRow == id { layout?.notchRow = nil }
        }
        return .none

      case let .searchChanged(text):
        state.search = text
        return .none

      case let .featureTapped(feature):
        state.panel = .feature(feature)
        state.preview = nil
        return .none

      case .backTapped:
        state.panel = .features
        state.preview = nil
        return .none

      case let .hovered(id):
        state.preview = id.flatMap { state.place(for: $0) }
        return .none

      case let .sizeTapped(id, size):
        guard state.isEditing, let widget = state.widgets.first(where: { $0.id == id }),
              case let .grid(sizes) = widget.place, sizes.contains(size)
        else { return .none }
        guard state.shownWidgets.contains(id), let index = state.saved?.placed.firstIndex(where: { $0.widget == id })
        else {
          // Off Home: the size waits for Add, and the copy takes it at once.
          state.chosenSizes[id] = size
          if state.preview?.widget == id { state.preview = state.place(for: id) }
          return .none
        }
        // On Home: the new size keeps the top left corner, and only if it fits there.
        guard let placement = state.saved?.placed[index],
              HomeLayout(notchRow: nil, placed: state.visible)
                .fits(size, column: placement.column, row: placement.row, ignoring: [id])
        else { return .none }
        state.$saved.withLock { $0?.placed[index].size = size }
        return .none

      case let .addTapped(id):
        guard state.isEditing, let place = state.place(for: id) else { return .none }
        switch place {
        case let .at(placement):
          state.$saved.withLock { $0?.placed.append(placement) }
        case .notchRow:
          state.$saved.withLock { $0?.notchRow = id }
        case .noRoom:
          return .none
        }
        state.preview = nil
        return .none

      case let .dropped(id, column, row):
        guard state.isEditing, state.shownWidgets.contains(id),
              let index = state.saved?.placed.firstIndex(where: { $0.widget == id }),
              let placement = state.saved?.placed[index],
              HomeLayout(notchRow: nil, placed: state.visible).fits(placement.size, column: column, row: row, ignoring: [id])
        else { return .none }
        state.$saved.withLock { layout in
          layout?.placed[index].column = column
          layout?.placed[index].row = row
        }
        return .none
      }
    }
  }
}
