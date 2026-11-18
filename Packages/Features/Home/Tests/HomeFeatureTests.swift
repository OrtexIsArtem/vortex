import ComposableArchitecture
import Testing
import VortexCore

@testable import FeatureHome

/// Home's layout as it lives on: saved in home.json, through features that go and come back.
@MainActor
struct HomeFeatureTests {
  func info(_ id: String, _ place: HomeWidgetPlace, name: String, featureName: String) -> WidgetInfo {
    let feature = FeatureID(String(id.split(separator: ".")[0]))
    return WidgetInfo(id: id, feature: feature, place: place, name: name, featureName: featureName, featureSymbol: "square")
  }

  var timer: WidgetInfo { info("timer.timer", .notchRow, name: "Timer", featureName: "Timer") }
  var clipboard: WidgetInfo { info("clipboard.history", .grid([.large, .medium]), name: "History", featureName: "Clipboard") }
  var shelf: WidgetInfo { info("shelf.files", .grid([.medium, .wide]), name: "Files", featureName: "Shelf") }
  var tasks: WidgetInfo { info("tasks.list", .grid([.medium]), name: "List", featureName: "Tasks") }
  var pinned: WidgetInfo { info("clipboard.pinned", .grid([.small, .medium]), name: "Pinned", featureName: "Clipboard") }

  /// Home as an update from stage 1 lays it out, in the editor: Timer in the notch row, Clipboard's history large at
  /// (0,0), Shelf medium at (2,0); Clipboard's pinned widget is off Home.
  func editingStore(saved: HomeLayout? = nil) async -> TestStoreOf<HomeFeature> {
    let widgets = [timer, clipboard, pinned, shelf]
    let store = makeStore(saved: saved ?? HomeLayout.initial([timer, clipboard, shelf]))
    await store.send(.widgetsChanged(widgets)) { $0.widgets = widgets }
    await store.send(.editTapped) { $0.isEditing = true }
    return store
  }

  /// A grid that one full widget fills.
  var fullGrid: HomeLayout {
    HomeLayout(notchRow: "timer.timer", placed: [Placement(widget: "shelf.files", size: .full, column: 0, row: 0)])
  }

  func makeStore(saved: HomeLayout? = nil) -> TestStoreOf<HomeFeature> {
    @Shared(.homeLayout) var layout
    $layout.withLock { $0 = saved }
    return TestStore(initialState: HomeFeature.State()) { HomeFeature() }
  }

  /// A fresh install has no widget until the user chooses features: nothing is written until there is one.
  @Test
  func theFirstLayoutWaitsForWidgetsThenIsSaved() async {
    let store = makeStore()
    await store.send(.widgetsChanged([]))
    #expect(store.state.saved == nil)
    await store.send(.widgetsChanged([timer, clipboard, shelf])) {
      $0.widgets = [self.timer, self.clipboard, self.shelf]
      $0.$saved.withLock { $0 = HomeLayout.initial([self.timer, self.clipboard, self.shelf]) }
    }
    #expect(store.state.notchRowWidget == "timer.timer")
    #expect(store.state.visible.map(\.widget) == ["clipboard.history", "shelf.files"])
  }

  /// A feature that goes takes its widget off Home, but the widget keeps its place in home.json.
  @Test
  func aRemovedFeaturesWidgetDisappearsButKeepsItsPlace() async {
    let saved = HomeLayout.initial([timer, clipboard, shelf])
    let store = makeStore(saved: saved)
    await store.send(.widgetsChanged([timer, shelf])) {
      $0.widgets = [self.timer, self.shelf]
      $0.$saved.withLock { $0?.placed[0].isAway = true }
    }
    #expect(store.state.visible.map(\.widget) == ["shelf.files"])
    #expect(store.state.saved?.placed.map(\.widget) == ["clipboard.history", "shelf.files"])
  }

  /// Back after its place was taken, a widget leaves the layout; the widget that took the place stays. Kept in
  /// home.json, so a relaunch in between changes nothing.
  @Test
  func aReturningWidgetWhosePlaceWasTakenLeavesTheLayout() async {
    var away = Placement(widget: "clipboard.history", size: .large, column: 0, row: 0)
    away.isAway = true
    let saved = HomeLayout(notchRow: nil, placed: [away, Placement(widget: "shelf.files", size: .wide, column: 0, row: 0)])
    let store = makeStore(saved: saved)
    await store.send(.widgetsChanged([clipboard, shelf])) {
      $0.widgets = [self.clipboard, self.shelf]
      $0.$saved.withLock { $0?.placed = [Placement(widget: "shelf.files", size: .wide, column: 0, row: 0)] }
    }
    #expect(store.state.visible.map(\.widget) == ["shelf.files"])
  }

  /// Back to a place that is still free, a widget shows there again.
  @Test
  func aReturningWidgetGetsItsFreePlaceBack() async {
    var away = Placement(widget: "clipboard.history", size: .large, column: 0, row: 0)
    away.isAway = true
    let store = makeStore(saved: HomeLayout(notchRow: nil, placed: [away]))
    await store.send(.widgetsChanged([clipboard])) {
      $0.widgets = [self.clipboard]
      $0.$saved.withLock { $0?.placed[0].isAway = false }
    }
    #expect(store.state.visible.map(\.widget) == ["clipboard.history"])
  }

  /// The row next to the notch shows its widget only while the widget's feature runs, and keeps it meanwhile.
  @Test
  func theNotchRowWidgetHidesWhileItsFeatureIsAway() async {
    let store = makeStore(saved: HomeLayout.initial([timer, clipboard]))
    await store.send(.widgetsChanged([clipboard])) {
      $0.widgets = [self.clipboard]
    }
    #expect(store.state.notchRowWidget == nil)
    #expect(store.state.saved?.notchRow == "timer.timer")
    await store.send(.widgetsChanged([timer, clipboard])) {
      $0.widgets = [self.timer, self.clipboard]
    }
    #expect(store.state.notchRowWidget == "timer.timer")
  }

  /// A feature added later doesn't put its widget on Home by itself.
  @Test
  func aFeatureAddedLaterDoesntGoOnHomeByItself() async {
    let store = makeStore(saved: HomeLayout.initial([timer, clipboard]))
    await store.send(.widgetsChanged([timer, clipboard, tasks])) {
      $0.widgets = [self.timer, self.clipboard, self.tasks]
    }
    #expect(store.state.visible.map(\.widget) == ["clipboard.history"])
  }

  // MARK: - The editor

  /// Edit Home turns Home into the editor, with the feature list in the panel; Done ends it and clears the search.
  @Test
  func editingStartsWithTheFeatureListAndDoneEndsIt() async {
    let store = makeStore(saved: HomeLayout.initial([timer, clipboard, shelf]))
    await store.send(.editTapped) { $0.isEditing = true }
    #expect(store.state.panel == .features)
    await store.send(.searchChanged("cl")) { $0.search = "cl" }
    await store.send(.doneTapped) {
      $0.isEditing = false
      $0.search = ""
    }
  }

  /// Closing the window, however it closes, ends the editor.
  @Test
  func closingTheWindowEndsEditing() async {
    let store = makeStore(saved: HomeLayout.initial([timer, clipboard, shelf]))
    await store.send(.editTapped) { $0.isEditing = true }
    await store.send(.windowClosed) { $0.isEditing = false }
  }

  /// Removing a widget in the editor frees its cells at once, in home.json too; the others don't move.
  @Test
  func removingAWidgetFreesItsCells() async {
    let store = makeStore(saved: HomeLayout.initial([timer, clipboard, shelf]))
    await store.send(.widgetsChanged([timer, clipboard, shelf])) {
      $0.widgets = [self.timer, self.clipboard, self.shelf]
    }
    // Outside the editor nothing is removed.
    await store.send(.removeTapped("shelf.files"))
    await store.send(.editTapped) { $0.isEditing = true }
    await store.send(.removeTapped("shelf.files")) {
      $0.$saved.withLock { $0?.placed.removeAll { $0.widget == "shelf.files" } }
    }
    #expect(store.state.saved?.placed == [Placement(widget: "clipboard.history", size: .large, column: 0, row: 0)])
    #expect(store.state.saved?.fits(.medium, column: 2, row: 0, ignoring: []) == true)
  }

  /// Removing the widget in the row next to the notch leaves the row to Home's title.
  @Test
  func removingTheNotchRowWidgetEmptiesTheRow() async {
    let store = makeStore(saved: HomeLayout.initial([timer, clipboard]))
    await store.send(.widgetsChanged([timer, clipboard])) {
      $0.widgets = [self.timer, self.clipboard]
    }
    await store.send(.editTapped) { $0.isEditing = true }
    await store.send(.removeTapped("timer.timer")) {
      $0.$saved.withLock { $0?.notchRow = nil }
    }
    #expect(store.state.notchRowWidget == nil)
  }

  /// The panel lists the features with widgets in sidebar order: those with a widget on Home first, then the others.
  @Test
  func thePanelListsFeaturesOnHomeFirstThenTheRest() {
    var state = HomeFeature.State()
    state.$saved.withLock { $0 = HomeLayout.initial([timer, clipboard, shelf]) }
    state.widgets = [clipboard, shelf, timer, tasks]
    #expect(state.panelSections.onHome == ["clipboard", "shelf", "timer"])
    #expect(state.panelSections.more == ["tasks"])
  }

  /// The search keeps the features whose name, or one of whose widgets' names, holds the text, in any case.
  @Test
  func searchFindsFeaturesAndWidgetsByName() {
    var state = HomeFeature.State()
    state.$saved.withLock { $0 = HomeLayout.initial([timer, clipboard, shelf]) }
    state.widgets = [clipboard, shelf, timer, tasks]
    state.search = "HIST"
    #expect(state.panelSections.onHome == ["clipboard"] && state.panelSections.more.isEmpty)
    state.search = " tas "
    #expect(state.panelSections.onHome.isEmpty && state.panelSections.more == ["tasks"])
    state.search = "zzz"
    #expect(state.panelSections.onHome.isEmpty && state.panelSections.more.isEmpty)
  }

  // MARK: - Sizes, the copy, Add and moving

  /// A feature's row opens its widgets in the panel; another feature or back to the list takes the copy away.
  @Test
  func aFeatureOpensItsWidgetsAndBackReturns() async {
    let store = await editingStore()
    await store.send(.featureTapped("clipboard")) { $0.panel = .feature("clipboard") }
    await store.send(.hovered("clipboard.pinned")) {
      $0.preview = .at(Placement(widget: "clipboard.pinned", size: .small, column: 2, row: 1))
    }
    await store.send(.featureTapped("shelf")) {
      $0.panel = .feature("shelf")
      $0.preview = nil
    }
    await store.send(.hovered("clipboard.pinned")) {
      $0.preview = .at(Placement(widget: "clipboard.pinned", size: .small, column: 2, row: 1))
    }
    await store.send(.backTapped) {
      $0.panel = .features
      $0.preview = nil
    }
  }

  /// While a widget's feature is away its place is free: another widget can take it, and the away one doesn't move.
  @Test
  func aWidgetCanTakeThePlaceOfOneWhoseFeatureWent() async {
    let store = makeStore(saved: HomeLayout.initial([timer, clipboard, shelf]))
    await store.send(.widgetsChanged([timer, tasks])) {
      $0.widgets = [self.timer, self.tasks]
      $0.$saved.withLock { layout in
        layout?.placed[0].isAway = true
        layout?.placed[1].isAway = true
      }
    }
    await store.send(.editTapped) { $0.isEditing = true }
    await store.send(.hovered("tasks.list")) {
      $0.preview = .at(Placement(widget: "tasks.list", size: .medium, column: 0, row: 0))
    }
    // The grid is empty, yet an away widget isn't dragged anywhere.
    await store.send(.dropped("clipboard.history", column: 2, row: 0))
  }

  /// Outside the editor nothing changes Home's layout.
  @Test
  func editsNeedTheEditor() async {
    let store = makeStore(saved: HomeLayout.initial([timer, clipboard, shelf]))
    await store.send(.widgetsChanged([timer, clipboard, pinned, shelf])) {
      $0.widgets = [self.timer, self.clipboard, self.pinned, self.shelf]
    }
    await store.send(.addTapped("clipboard.pinned"))
    await store.send(.sizeTapped("clipboard.history", .medium))
    await store.send(.dropped("shelf.files", column: 2, row: 1))
  }

  /// Hovering a widget in the panel puts its copy where it would go: its chosen size in the first place it fits.
  @Test
  func hoveringAWidgetShowsItsCopyWhereItWouldGo() async {
    let store = await editingStore()
    await store.send(.hovered("clipboard.pinned")) {
      $0.preview = .at(Placement(widget: "clipboard.pinned", size: .small, column: 2, row: 1))
    }
    await store.send(.hovered(nil)) { $0.preview = nil }
    // A widget already on Home has no copy.
    await store.send(.hovered("shelf.files"))
    let full = await editingStore(saved: fullGrid)
    await full.send(.hovered("clipboard.pinned")) { $0.preview = .noRoom("clipboard.pinned") }
  }

  /// A size chosen in the panel is the one the copy and Add use.
  @Test
  func aChosenSizeIsWhatTheCopyAndAddUse() async {
    let store = await editingStore()
    await store.send(.hovered("clipboard.pinned")) {
      $0.preview = .at(Placement(widget: "clipboard.pinned", size: .small, column: 2, row: 1))
    }
    await store.send(.sizeTapped("clipboard.pinned", .medium)) {
      $0.chosenSizes["clipboard.pinned"] = .medium
      $0.preview = .at(Placement(widget: "clipboard.pinned", size: .medium, column: 2, row: 1))
    }
    await store.send(.addTapped("clipboard.pinned")) {
      $0.$saved.withLock { $0?.placed.append(Placement(widget: "clipboard.pinned", size: .medium, column: 2, row: 1)) }
      $0.preview = nil
    }
    // The next edit starts with every widget at its first size again.
    await store.send(.doneTapped) {
      $0.isEditing = false
      $0.chosenSizes = [:]
    }
  }

  /// Add puts the widget where its copy was, and saves.
  @Test
  func addPutsTheWidgetWhereItsCopyWas() async {
    let store = await editingStore()
    await store.send(.hovered("clipboard.pinned")) {
      $0.preview = .at(Placement(widget: "clipboard.pinned", size: .small, column: 2, row: 1))
    }
    await store.send(.addTapped("clipboard.pinned")) {
      $0.$saved.withLock { $0?.placed.append(Placement(widget: "clipboard.pinned", size: .small, column: 2, row: 1)) }
      $0.preview = nil
    }
    #expect(store.state.panelSections.onHome == ["timer", "clipboard", "shelf"])
    // On Home already: a second Add changes nothing.
    await store.send(.addTapped("clipboard.pinned"))
  }

  /// Without room Add does nothing.
  @Test
  func addDoesNothingWithoutRoom() async {
    let store = await editingStore(saved: fullGrid)
    await store.send(.addTapped("clipboard.pinned"))
    #expect(store.state.saved == fullGrid)
  }

  /// A widget of the notch row goes back to its row, while the row is free.
  @Test
  func aNotchRowWidgetGoesBackToItsRow() async {
    let store = await editingStore()
    // The row holds one widget.
    let clock = info("clock.row", .notchRow, name: "Clock", featureName: "Clock")
    await store.send(.widgetsChanged([timer, clipboard, pinned, shelf, clock])) {
      $0.widgets = [self.timer, self.clipboard, self.pinned, self.shelf, clock]
    }
    await store.send(.hovered("clock.row")) { $0.preview = .noRoom("clock.row") }
    await store.send(.hovered(nil)) { $0.preview = nil }
    await store.send(.removeTapped("timer.timer")) { $0.$saved.withLock { $0?.notchRow = nil } }
    await store.send(.hovered("timer.timer")) { $0.preview = .notchRow("timer.timer") }
    await store.send(.addTapped("timer.timer")) {
      $0.$saved.withLock { $0?.notchRow = "timer.timer" }
      $0.preview = nil
    }
  }

  /// A widget on Home changes size in place, its top left corner kept, and only when the new size fits there.
  @Test
  func aPlacedWidgetChangesSizeOnlyIfItFits() async {
    let store = await editingStore()
    // Wide from (2,0) would leave the grid.
    await store.send(.sizeTapped("shelf.files", .wide))
    await store.send(.sizeTapped("clipboard.history", .medium)) {
      $0.$saved.withLock { $0?.placed[0].size = .medium }
    }
    // Large again fits: its cells are free.
    await store.send(.sizeTapped("clipboard.history", .large)) {
      $0.$saved.withLock { $0?.placed[0].size = .large }
    }
    // A size the widget doesn't offer is never applied.
    await store.send(.sizeTapped("clipboard.history", .small))
  }

  /// A dragged widget lands with its top left corner on a cell, and only where it fits whole.
  @Test
  func droppingSnapsToTheCellOnlyWhereItFits() async {
    let store = await editingStore()
    await store.send(.dropped("shelf.files", column: 2, row: 1)) {
      $0.$saved.withLock { $0?.placed[1].row = 1 }
    }
    // Onto Clipboard's cells, and past the grid's edge: it stays.
    await store.send(.dropped("shelf.files", column: 1, row: 0))
    await store.send(.dropped("shelf.files", column: 3, row: 1))
    // A widget that isn't on Home doesn't move in.
    await store.send(.dropped("clipboard.pinned", column: 2, row: 0))
  }
}
