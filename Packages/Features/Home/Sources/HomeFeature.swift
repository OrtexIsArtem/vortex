import ComposableArchitecture
import Foundation
import VortexCore

extension SharedKey where Self == FileStorageKey<HomeLayout?>.Default {
  /// Where the widgets are on Home: DataFolder/home.json. Nil until Home first had a widget to lay out.
  static var homeLayout: Self {
    Self[.fileStorage(DataFolder.url.appending(path: "home.json")), default: nil]
  }
}

/// Home: the layout of the running features' widgets, saved in home.json. The editor changes a draft of it, which only
/// Done keeps.
@Reducer
struct HomeFeature: Sendable {
  @ObservableState
  struct State: Equatable {
    @Shared(.homeLayout) var saved
    /// The editor's copy of the layout, taken as it opens: every edit changes only this, and only Done keeps it in
    /// `saved`. Nil outside the editor.
    var draft: HomeLayout?
    /// The widgets the running features offer now, in sidebar order, as the shell tells them.
    var widgets: [HomeWidgetInfo] = []
    /// Features' pages asking for their first widget on Home.
    @Shared(.homeAddRequests) var addRequests
    /// What the shell hears back: the features with a widget on Home.
    @Shared(.featuresOnHome) var featuresOnHome

    var available: Set<String> { Set(widgets.map(\.id)) }

    /// The layout Home shows: the editor's draft while it is open, the saved one otherwise.
    var layout: HomeLayout? {
      isEditing ? draft : saved
    }

    /// The widgets on the grid now: those whose feature runs. An away widget's feature doesn't run: once its feature
    /// is back, the widget either shows again or has left the layout.
    var visible: [Placement] {
      layout?.visible(available) ?? []
    }

    /// The widget in the row next to the notch, while its feature runs.
    var notchRowWidget: String? {
      layout?.notchRowWidget(available)
    }

    /// The widgets that show on Home now: on the grid or in the row next to the notch.
    var shownWidgets: Set<String> {
      Set(visible.map(\.widget) + [notchRowWidget].compactMap { $0 })
    }

    /// The features with a widget on Home as it is saved: what the shell hears. The editor's draft counts once Done
    /// keeps it.
    var featuresKept: Set<FeatureID> {
      let grid = (saved?.visible(available) ?? []).map(\.widget)
      let kept = Set(grid + [saved?.notchRowWidget(available)].compactMap { $0 })
      return Set(widgets.filter { kept.contains($0.id) }.map(\.feature))
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

    /// Home once the widget on the grid is dragged so its top left corner lands on `column`, `row`, the widgets in its
    /// way moved aside (`HomeLayout.moving`). Nil outside the editor, or where it can't land: it goes back. The drop and
    /// the grid while dragging both read this, so the drop keeps what showed.
    func layout(moving id: String, column: Int, row: Int) -> HomeLayout? {
      guard isEditing else { return nil }
      return draft?.moving(id, column: column, row: row, available: available)
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
    /// Home starts (`HomeModule.setEnabled`): it follows the shell's running widgets and the pages' requests.
    case started
    case stopped
    /// The running features' widgets, whenever the shell tells them anew.
    case widgetsChanged([HomeWidgetInfo])
    /// The features' pages asking for their first widget on Home, whenever the requests change.
    case addRequestsChanged([FeatureID])
    /// The pencil, or "Edit Home" in Home's menu.
    case editTapped
    /// Done keeps the edits; so does "More widgets in Features", which is Done, then the catalog.
    case doneTapped
    /// Cancel, and leaving Home's tab: Home goes back to how it was when the editor opened.
    case cancelTapped
    /// The window closed, however it did: the editor ends with it, as with Cancel.
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
    /// A widget on Home dragged so its top left corner is over a cell: the widgets in its way move aside.
    case dropped(String, column: Int, row: Int)
  }

  enum CancelID {
    case following
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .started:
        return follow()

      case .stopped:
        return .cancel(id: CancelID.following)

      case let .addRequestsChanged(features):
        // While the editor is open a request waits: it goes on Home as the editor ends, into the layout kept.
        guard !features.isEmpty, !state.isEditing else { return .none }
        let after = adding(features, to: state.saved, state)
        if after != state.saved { state.$saved.withLock { $0 = after } }
        // Each request goes once taken, with or without room.
        state.$addRequests.withLock { $0.removeAll { features.contains($0) } }
        return .none

      case let .widgetsChanged(widgets):
        state.widgets = widgets
        let available = Set(widgets.map(\.id))
        if let saved = state.saved {
          let reconciled = saved.reconciled(available: available)
          if reconciled != saved { state.$saved.withLock { $0 = reconciled } }
        } else if !widgets.isEmpty {
          // The first layout waits for a widget: before the user chooses features there is none, and an empty layout
          // saved then would leave the chosen ones off as if added later.
          state.$saved.withLock { $0 = HomeLayout.initial(widgets) }
        }
        // The draft follows the same rules on its own, so whichever layout the editor leaves has followed them: Done's
        // or the one from before. A draft taken before there was a layout is the first one.
        if state.isEditing {
          state.draft = state.draft?.reconciled(available: available) ?? state.saved
        }
        return .none

      case .editTapped:
        guard !state.isEditing else { return .none }
        state.isEditing = true
        state.draft = state.saved
        return .none

      case .doneTapped:
        return endEditing(&state, keepingDraft: true)

      case .cancelTapped, .windowClosed:
        return endEditing(&state, keepingDraft: false)

      case let .removeTapped(id):
        guard state.isEditing else { return .none }
        // The other widgets stay where they are.
        state.draft?.placed.removeAll { $0.widget == id }
        if state.draft?.notchRow == id { state.draft?.notchRow = nil }
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
        guard state.shownWidgets.contains(id), let index = state.draft?.placed.firstIndex(where: { $0.widget == id })
        else {
          // Off Home: the size waits for Add, and the copy takes it at once.
          state.chosenSizes[id] = size
          if state.preview?.widget == id { state.preview = state.place(for: id) }
          return .none
        }
        // On Home: the new size keeps the top left corner, and only if it fits there.
        guard let placement = state.draft?.placed[index],
              HomeLayout(notchRow: nil, placed: state.visible)
                .fits(size, column: placement.column, row: placement.row, ignoring: [id])
        else { return .none }
        state.draft?.placed[index].size = size
        return .none

      case let .addTapped(id):
        guard state.isEditing, let place = state.place(for: id) else { return .none }
        switch place {
        case let .at(placement):
          state.draft?.placed.append(placement)
        case .notchRow:
          state.draft?.notchRow = id
        case .noRoom:
          return .none
        }
        state.preview = nil
        return .none

      case let .dropped(id, column, row):
        // The widgets in its way move aside; where they can't, it goes back and nothing moves.
        guard let moved = state.layout(moving: id, column: column, row: row) else { return .none }
        state.draft = moved
        return .none
      }
    }
    // The shell's "On Home" follows what is kept, however it changed.
    .onChange(of: \.featuresKept) { _, features in
      Reduce { state, _ in
        state.$featuresOnHome.withLock { $0 = features }
        return .none
      }
    }
  }

  /// Ends the editor; the next one starts again with the feature list. Done keeps the draft, in one write and none when
  /// nothing changed; any other way out leaves the saved layout as it was. Requests that waited for the editor go on
  /// Home now, into the layout kept, in the same write.
  private func endEditing(_ state: inout State, keepingDraft: Bool) -> Effect<Action> {
    let wasEditing = state.isEditing
    let draft = state.draft
    state.isEditing = false
    state.draft = nil
    state.panel = .features
    state.search = ""
    state.preview = nil
    state.chosenSizes = [:]
    guard wasEditing else { return .none }
    let requests = state.addRequests
    let kept = adding(requests, to: keepingDraft ? draft : state.saved, state)
    if kept != state.saved { state.$saved.withLock { $0 = kept } }
    if !requests.isEmpty { state.$addRequests.withLock { $0.removeAll { requests.contains($0) } } }
    return .none
  }

  /// `layout` with each feature's first widget put on it, in the order asked, as "Add to Home" puts it.
  private func adding(_ features: [FeatureID], to layout: HomeLayout?, _ state: State) -> HomeLayout? {
    guard !features.isEmpty else { return layout }
    let before = layout ?? HomeLayout()
    let after = features.reduce(before) { layout, feature in
      guard let widget = state.widgets.first(where: { $0.feature == feature }) else { return layout }
      return layout.adding(widget, available: state.available)
    }
    return after == before ? layout : after
  }

  /// Follows the shell's running widgets and the pages' requests, in the order they change: the shell tells the widgets
  /// before a page can ask for one of them.
  private func follow() -> Effect<Action> {
    .run { send in
      @SharedReader(.runningHomeWidgets) var running
      @SharedReader(.homeAddRequests) var requests
      enum Change {
        case widgets([HomeWidgetInfo])
        case requests([FeatureID])
      }
      let (changes, continuation) = AsyncStream.makeStream(of: Change.self)
      // Each publisher gives its value now, then every change. Until the shell first tells the running widgets there is
      // nothing to follow: Home doesn't take "not told yet" for "none run", which would send every widget away.
      let subscriptions = [
        $running.publisher.compactMap { $0 }.removeDuplicates().sink { continuation.yield(.widgets($0)) },
        $requests.publisher.removeDuplicates().sink { continuation.yield(.requests($0)) },
      ]
      defer { subscriptions.forEach { $0.cancel() } }
      for await change in changes {
        switch change {
        case let .widgets(widgets): await send(.widgetsChanged(widgets))
        case let .requests(features): await send(.addRequestsChanged(features))
        }
      }
    }
    .cancellable(id: CancelID.following, cancelInFlight: true)
  }
}
