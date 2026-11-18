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
      }
    }
  }
}
