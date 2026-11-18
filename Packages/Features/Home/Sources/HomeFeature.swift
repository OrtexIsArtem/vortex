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
  }

  enum Action: Equatable {
    /// The running features' widgets, sent by Home's view whenever they change.
    case widgetsChanged([WidgetInfo])
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
      }
    }
  }
}
