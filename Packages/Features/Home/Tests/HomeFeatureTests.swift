import ComposableArchitecture
import Foundation
@_spi(Internals) import Sharing
import Testing
import VortexCore

@testable import FeatureHome

/// home.json in a file system of the test's own: what it holds, and how many times it was written.
struct HomeFile {
  let files = LockIsolated<[URL: Data]>([:])
  let writes = LockIsolated(0)

  var storage: FileStorage {
    // Each write is saved at once and then asks for a later one, which finds nothing more to save.
    .inMemory(fileSystem: files, asyncAfter: { [writes] _, work in
      writes.withValue { $0 += 1 }
      work.perform()
    })
  }

  var layout: HomeLayout? {
    files.value.values.first.flatMap { try? JSONDecoder().decode(HomeLayout.self, from: $0) }
  }
}

/// Home's layout as it lives on: saved in home.json, through features that go and come back.
@MainActor
struct HomeFeatureTests {
  func info(_ id: String, _ place: HomeWidgetPlace, name: String, featureName: String) -> HomeWidgetInfo {
    let feature = FeatureID(String(id.split(separator: ".")[0]))
    return HomeWidgetInfo(id: id, feature: feature, place: place, name: name, featureName: featureName, featureSymbol: "square")
  }

  var timer: HomeWidgetInfo { info("timer.timer", .notchRow, name: "Timer", featureName: "Timer") }
  var clipboard: HomeWidgetInfo { info("clipboard.history", .grid([.large, .medium]), name: "History", featureName: "Clipboard") }
  var shelf: HomeWidgetInfo { info("shelf.files", .grid([.medium, .wide]), name: "Files", featureName: "Shelf") }
  var tasks: HomeWidgetInfo { info("tasks.list", .grid([.medium]), name: "List", featureName: "Tasks") }
  var pinned: HomeWidgetInfo { info("clipboard.pinned", .grid([.small, .medium]), name: "Pinned", featureName: "Clipboard") }

  /// Home as an update from stage 1 lays it out, in the editor: Timer in the notch row, Clipboard's history large at
  /// (0,0), Shelf medium at (2,0); Clipboard's pinned widget is off Home.
  func editingStore(saved: HomeLayout? = nil) async -> TestStoreOf<HomeFeature> {
    let widgets = [timer, clipboard, pinned, shelf]
    let layout = saved ?? HomeLayout.initial([timer, clipboard, shelf])
    let store = makeStore(saved: layout)
    let shown = [layout.notchRow].compactMap { $0 } + layout.placed.map(\.widget)
    await store.send(.widgetsChanged(widgets)) {
      $0.widgets = widgets
      $0.$featuresOnHome.withLock { $0 = Set(widgets.filter { shown.contains($0.id) }.map(\.feature)) }
    }
    await store.send(.editTapped) {
      $0.isEditing = true
      $0.draft = layout
    }
    return store
  }

  /// A grid that one full widget fills.
  var fullGrid: HomeLayout {
    HomeLayout(notchRow: "timer.timer", placed: [Placement(widget: "shelf.files", size: .full, column: 0, row: 0)])
  }

  func makeStore(saved: HomeLayout? = nil, addRequests: [FeatureID] = []) -> TestStoreOf<HomeFeature> {
    @Shared(.homeLayout) var layout
    $layout.withLock { $0 = saved }
    @Shared(.homeAddRequests) var requests
    $requests.withLock { $0 = addRequests }
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
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard", "shelf"] }
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
      $0.$saved.withLock { $0?.placed[0].away = 1 }
      $0.$featuresOnHome.withLock { $0 = ["timer", "shelf"] }
    }
    #expect(store.state.visible.map(\.widget) == ["shelf.files"])
    #expect(store.state.saved?.placed.map(\.widget) == ["clipboard.history", "shelf.files"])
  }

  /// Back after its place was taken, a widget leaves the layout; the widget that took the place stays. Kept in
  /// home.json, so a relaunch in between changes nothing.
  @Test
  func aReturningWidgetWhosePlaceWasTakenLeavesTheLayout() async {
    var returning = Placement(widget: "clipboard.history", size: .large, column: 0, row: 0)
    returning.away = 1
    let saved = HomeLayout(notchRow: nil, placed: [returning, Placement(widget: "shelf.files", size: .wide, column: 0, row: 0)])
    let store = makeStore(saved: saved)
    await store.send(.widgetsChanged([clipboard, shelf])) {
      $0.widgets = [self.clipboard, self.shelf]
      $0.$saved.withLock { $0?.placed = [Placement(widget: "shelf.files", size: .wide, column: 0, row: 0)] }
      $0.$featuresOnHome.withLock { $0 = ["shelf"] }
    }
    #expect(store.state.visible.map(\.widget) == ["shelf.files"])
  }

  /// When nothing ran (safe mode), a widget that went long ago and the widget that took its place come back together:
  /// the one that showed last keeps the place, and the other leaves the layout.
  @Test
  func theWidgetThatShowedLastKeepsItsPlace() async {
    var returning = Placement(widget: "clipboard.history", size: .large, column: 0, row: 0)
    returning.away = 1
    let shelfPlace = Placement(widget: "shelf.files", size: .medium, column: 0, row: 0)
    let store = makeStore(saved: HomeLayout(notchRow: nil, placed: [returning, shelfPlace]))
    // Nothing runs: Shelf goes too, after Clipboard.
    await store.send(.widgetsChanged([])) {
      $0.$saved.withLock { $0?.placed[1].away = 2 }
    }
    await store.send(.widgetsChanged([clipboard, shelf])) {
      $0.widgets = [self.clipboard, self.shelf]
      $0.$saved.withLock { $0?.placed = [shelfPlace] }
      $0.$featuresOnHome.withLock { $0 = ["shelf"] }
    }
  }

  /// Back to a place that is still free, a widget shows there again.
  @Test
  func aReturningWidgetGetsItsFreePlaceBack() async {
    var returning = Placement(widget: "clipboard.history", size: .large, column: 0, row: 0)
    returning.away = 1
    let store = makeStore(saved: HomeLayout(notchRow: nil, placed: [returning]))
    await store.send(.widgetsChanged([clipboard])) {
      $0.widgets = [self.clipboard]
      $0.$saved.withLock { $0?.placed[0].away = nil }
      $0.$featuresOnHome.withLock { $0 = ["clipboard"] }
    }
    #expect(store.state.visible.map(\.widget) == ["clipboard.history"])
  }

  /// The row next to the notch shows its widget only while the widget's feature runs, and keeps it meanwhile.
  @Test
  func theNotchRowWidgetHidesWhileItsFeatureIsAway() async {
    let store = makeStore(saved: HomeLayout.initial([timer, clipboard]))
    await store.send(.widgetsChanged([clipboard])) {
      $0.widgets = [self.clipboard]
      $0.$featuresOnHome.withLock { $0 = ["clipboard"] }
    }
    #expect(store.state.notchRowWidget == nil)
    #expect(store.state.saved?.notchRow == "timer.timer")
    await store.send(.widgetsChanged([timer, clipboard])) {
      $0.widgets = [self.timer, self.clipboard]
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard"] }
    }
    #expect(store.state.notchRowWidget == "timer.timer")
  }

  /// A feature added later doesn't put its widget on Home by itself.
  @Test
  func aFeatureAddedLaterDoesntGoOnHomeByItself() async {
    let store = makeStore(saved: HomeLayout.initial([timer, clipboard]))
    await store.send(.widgetsChanged([timer, clipboard, tasks])) {
      $0.widgets = [self.timer, self.clipboard, self.tasks]
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard"] }
    }
    #expect(store.state.visible.map(\.widget) == ["clipboard.history"])
  }

  // MARK: - The editor

  /// Edit Home turns Home into the editor, with the feature list in the panel and a draft of the layout; Done ends it
  /// and clears the search.
  @Test
  func editingStartsWithTheFeatureListAndDoneEndsIt() async {
    let saved = HomeLayout.initial([timer, clipboard, shelf])
    let store = makeStore(saved: saved)
    await store.send(.editTapped) {
      $0.isEditing = true
      $0.draft = saved
    }
    #expect(store.state.panel == .features)
    await store.send(.searchChanged("cl")) { $0.search = "cl" }
    // A second Edit Home changes nothing.
    await store.send(.editTapped)
    await store.send(.doneTapped) {
      $0.isEditing = false
      $0.draft = nil
      $0.search = ""
    }
  }

  /// Closing the window, however it closes, ends the editor.
  @Test
  func closingTheWindowEndsEditing() async {
    let saved = HomeLayout.initial([timer, clipboard, shelf])
    let store = makeStore(saved: saved)
    await store.send(.editTapped) {
      $0.isEditing = true
      $0.draft = saved
    }
    await store.send(.windowClosed) {
      $0.isEditing = false
      $0.draft = nil
    }
  }

  /// Removing a widget in the editor frees its cells at once; the others don't move.
  @Test
  func removingAWidgetFreesItsCells() async {
    let saved = HomeLayout.initial([timer, clipboard, shelf])
    let store = makeStore(saved: saved)
    await store.send(.widgetsChanged([timer, clipboard, shelf])) {
      $0.widgets = [self.timer, self.clipboard, self.shelf]
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard", "shelf"] }
    }
    // Outside the editor nothing is removed.
    await store.send(.removeTapped("shelf.files"))
    await store.send(.editTapped) {
      $0.isEditing = true
      $0.draft = saved
    }
    await store.send(.removeTapped("shelf.files")) {
      $0.draft?.placed.removeAll { $0.widget == "shelf.files" }
    }
    #expect(store.state.visible == [Placement(widget: "clipboard.history", size: .large, column: 0, row: 0)])
    #expect(store.state.draft?.fits(.medium, column: 2, row: 0, ignoring: []) == true)
  }

  /// Removing the widget in the row next to the notch leaves the row to Home's title.
  @Test
  func removingTheNotchRowWidgetEmptiesTheRow() async {
    let saved = HomeLayout.initial([timer, clipboard])
    let store = makeStore(saved: saved)
    await store.send(.widgetsChanged([timer, clipboard])) {
      $0.widgets = [self.timer, self.clipboard]
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard"] }
    }
    await store.send(.editTapped) {
      $0.isEditing = true
      $0.draft = saved
    }
    await store.send(.removeTapped("timer.timer")) {
      $0.draft?.notchRow = nil
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
        layout?.placed[0].away = 1
        layout?.placed[1].away = 1
      }
      $0.$featuresOnHome.withLock { $0 = ["timer"] }
    }
    let saved = store.state.saved
    await store.send(.editTapped) {
      $0.isEditing = true
      $0.draft = saved
    }
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
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard", "shelf"] }
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
      $0.draft?.placed.append(Placement(widget: "clipboard.pinned", size: .medium, column: 2, row: 1))
      $0.preview = nil
    }
    // The next edit starts with every widget at its first size again.
    let draft = store.state.draft
    await store.send(.doneTapped) {
      $0.isEditing = false
      $0.$saved.withLock { $0 = draft }
      $0.draft = nil
      $0.chosenSizes = [:]
    }
  }

  /// Add puts the widget where its copy was.
  @Test
  func addPutsTheWidgetWhereItsCopyWas() async {
    let store = await editingStore()
    await store.send(.hovered("clipboard.pinned")) {
      $0.preview = .at(Placement(widget: "clipboard.pinned", size: .small, column: 2, row: 1))
    }
    await store.send(.addTapped("clipboard.pinned")) {
      $0.draft?.placed.append(Placement(widget: "clipboard.pinned", size: .small, column: 2, row: 1))
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
    await store.send(.removeTapped("timer.timer")) {
      $0.draft?.notchRow = nil
    }
    await store.send(.hovered("timer.timer")) { $0.preview = .notchRow("timer.timer") }
    await store.send(.addTapped("timer.timer")) {
      $0.draft?.notchRow = "timer.timer"
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
      $0.draft?.placed[0].size = .medium
    }
    // Large again fits: its cells are free.
    await store.send(.sizeTapped("clipboard.history", .large)) {
      $0.draft?.placed[0].size = .large
    }
    // A size the widget doesn't offer is never applied.
    await store.send(.sizeTapped("clipboard.history", .small))
  }

  /// A dragged widget lands with its top left corner on a cell, and the widgets in its way move aside: first to the
  /// place it left. Where they can't all fit, it goes back and nothing moves.
  @Test
  func droppingPushesTheWidgetsInTheWay() async {
    // The owner's Home: Shelf at (0,0), Clipboard at (2,0).
    let store = await editingStore(saved: HomeLayout(notchRow: "timer.timer", placed: [
      Placement(widget: "shelf.files", size: .medium, column: 0, row: 0),
      Placement(widget: "clipboard.history", size: .large, column: 2, row: 0),
    ]))
    // Shelf wouldn't fit anywhere around Clipboard at (1,0).
    await store.send(.dropped("clipboard.history", column: 1, row: 0))
    // Onto Shelf: they swap.
    await store.send(.dropped("clipboard.history", column: 0, row: 0)) {
      $0.draft?.placed[0].column = 2
      $0.draft?.placed[1].column = 0
    }
    // Nothing in the way.
    await store.send(.dropped("shelf.files", column: 2, row: 1)) {
      $0.draft?.placed[0].row = 1
    }
    // Past the grid's edge it stays.
    await store.send(.dropped("shelf.files", column: 3, row: 1))
    // A widget that isn't on Home doesn't move in.
    await store.send(.dropped("clipboard.pinned", column: 2, row: 0))
  }

  // MARK: - What Done keeps, and every other way out

  /// The editor's four kinds of edit, each changing only its draft: Clipboard dragged onto Shelf, Shelf removed,
  /// Clipboard made medium, and Clipboard's pinned widget added at medium.
  func edit(_ store: TestStoreOf<HomeFeature>) async {
    await store.send(.dropped("clipboard.history", column: 2, row: 0)) {
      $0.draft?.placed[0].column = 2
      $0.draft?.placed[1].column = 0
    }
    await store.send(.removeTapped("shelf.files")) {
      $0.draft?.placed.remove(at: 1)
    }
    await store.send(.sizeTapped("clipboard.history", .medium)) {
      $0.draft?.placed[0].size = .medium
    }
    await store.send(.sizeTapped("clipboard.pinned", .medium)) {
      $0.chosenSizes["clipboard.pinned"] = .medium
    }
    await store.send(.addTapped("clipboard.pinned")) {
      $0.draft?.placed.append(Placement(widget: "clipboard.pinned", size: .medium, column: 0, row: 0))
    }
  }

  /// Cancel puts Home back as it was when the editor opened: a drop, a remove, a size and an Add all go.
  @Test
  func cancelPutsHomeBack() async {
    await editsGo(by: .cancelTapped)
  }

  /// So does the window closing, however it closes (Esc, a click outside, a shortcut, the menu bar icon).
  @Test
  func closingTheWindowPutsHomeBack() async {
    await editsGo(by: .windowClosed)
  }

  /// Each way out but Done, as its own test: the cases of one parameterized test share their shared state.
  func editsGo(by wayOut: HomeFeature.Action) async {
    let store = await editingStore()
    let saved = store.state.saved
    let shown = store.state.visible
    await edit(store)
    #expect(store.state.visible != shown)
    await store.send(wayOut) {
      $0.isEditing = false
      $0.draft = nil
      $0.chosenSizes = [:]
    }
    #expect(store.state.saved == saved)
    #expect(store.state.visible == shown)
    #expect(store.state.notchRowWidget == "timer.timer")
  }

  /// Nothing the editor changes reaches home.json before Done; Done writes it once, and not at all when nothing
  /// changed.
  @Test
  func doneWritesHomeJSONOnceAndNothingIsWrittenBefore() async throws {
    let file = HomeFile()
    try await withDependencies { $0.defaultFileStorage = file.storage } operation: {
      let store = await editingStore()
      let before = try #require(file.layout)
      let writes = file.writes.value
      await edit(store)
      #expect(file.layout == before)
      #expect(file.writes.value == writes)
      let draft = store.state.draft
      // Not exhaustive for Done alone: an expectation's `$saved.withLock` writes home.json itself.
      store.exhaustivity = .off
      await store.send(.doneTapped)
      store.exhaustivity = .on
      #expect(store.state.saved == draft)
      #expect(!store.state.isEditing && store.state.draft == nil)
      #expect(store.state.featuresOnHome == ["timer", "clipboard"])
      #expect(file.writes.value == writes + 1)
      #expect(file.layout == draft)
      await store.send(.editTapped) {
        $0.isEditing = true
        $0.draft = draft
      }
      await store.send(.doneTapped) {
        $0.isEditing = false
        $0.draft = nil
      }
      #expect(file.writes.value == writes + 1)
      // Nor does Cancel.
      await store.send(.editTapped) {
        $0.isEditing = true
        $0.draft = draft
      }
      await store.send(.removeTapped("clipboard.pinned")) {
        $0.draft?.placed.remove(at: 1)
      }
      await store.send(.cancelTapped) {
        $0.isEditing = false
        $0.draft = nil
      }
      #expect(file.writes.value == writes + 1)
      #expect(file.layout == draft)
    }
  }

  /// A feature that goes while the editor is open takes its widget away from what is saved and from the draft alike,
  /// and its place is free in both. After Done the widget that took the place keeps it, and the one coming back leaves.
  @Test
  func aWidgetThatWentWhileEditingLeavesWhenDoneGaveItsPlaceAway() async {
    let store = await widgetGoesWhileEditing(then: .doneTapped)
    await store.send(.widgetsChanged([timer, clipboard, pinned, shelf])) {
      $0.widgets = [self.timer, self.clipboard, self.pinned, self.shelf]
      $0.$saved.withLock { _ = $0?.placed.remove(at: 1) }
    }
  }

  /// After Cancel nobody took its place, and the widget shows there again.
  @Test
  func aWidgetThatWentWhileEditingShowsAgainAfterCancel() async {
    let store = await widgetGoesWhileEditing(then: .cancelTapped)
    await store.send(.widgetsChanged([timer, clipboard, pinned, shelf])) {
      $0.widgets = [self.timer, self.clipboard, self.pinned, self.shelf]
      $0.$saved.withLock { $0?.placed[1].away = nil }
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard", "shelf"] }
    }
  }

  /// Shelf goes while the editor is open, Clipboard's pinned widget takes its place in the draft, and the editor ends.
  func widgetGoesWhileEditing(then wayOut: HomeFeature.Action) async -> TestStoreOf<HomeFeature> {
    let store = await editingStore()
    await store.send(.widgetsChanged([timer, clipboard, pinned])) {
      $0.widgets = [self.timer, self.clipboard, self.pinned]
      $0.$saved.withLock { $0?.placed[1].away = 1 }
      $0.draft?.placed[1].away = 1
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard"] }
    }
    await store.send(.addTapped("clipboard.pinned")) {
      $0.draft?.placed.append(Placement(widget: "clipboard.pinned", size: .small, column: 2, row: 0))
    }
    let draft = store.state.draft
    await store.send(wayOut) {
      $0.isEditing = false
      if wayOut == .doneTapped { $0.$saved.withLock { $0 = draft } }
      $0.draft = nil
    }
    return store
  }

  /// A widget that comes back while the editor is open shows again where it can, in each layout on its own: in what is
  /// saved its place is free; in the draft another widget took it, so it leaves. Done keeps the draft.
  @Test
  func aWidgetThatCameBackWhileEditingIsOffAfterDone() async {
    let store = await widgetComesBackWhileEditing()
    let draft = store.state.draft
    await store.send(.doneTapped) {
      $0.isEditing = false
      $0.$saved.withLock { $0 = draft }
      $0.draft = nil
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard"] }
    }
  }

  /// Cancel keeps what is saved, where it showed again.
  @Test
  func aWidgetThatCameBackWhileEditingShowsAfterCancel() async {
    let store = await widgetComesBackWhileEditing()
    await store.send(.cancelTapped) {
      $0.isEditing = false
      $0.draft = nil
    }
    #expect(store.state.visible.map(\.widget) == ["clipboard.history", "shelf.files"])
  }

  /// Shelf is away as the editor opens, Clipboard's pinned widget takes its place in the draft, and Shelf comes back.
  func widgetComesBackWhileEditing() async -> TestStoreOf<HomeFeature> {
    var away = Placement(widget: "shelf.files", size: .medium, column: 2, row: 0)
    away.away = 1
    let saved = HomeLayout(
      notchRow: "timer.timer",
      placed: [Placement(widget: "clipboard.history", size: .large, column: 0, row: 0), away]
    )
    let store = makeStore(saved: saved)
    await store.send(.widgetsChanged([timer, clipboard, pinned])) {
      $0.widgets = [self.timer, self.clipboard, self.pinned]
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard"] }
    }
    await store.send(.editTapped) {
      $0.isEditing = true
      $0.draft = saved
    }
    await store.send(.addTapped("clipboard.pinned")) {
      $0.draft?.placed.append(Placement(widget: "clipboard.pinned", size: .small, column: 2, row: 0))
    }
    await store.send(.widgetsChanged([timer, clipboard, pinned, shelf])) {
      $0.widgets = [self.timer, self.clipboard, self.pinned, self.shelf]
      $0.$saved.withLock { $0?.placed[1].away = nil }
      $0.draft?.placed.remove(at: 1)
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard", "shelf"] }
    }
    return store
  }

  /// An "Add to Home" that comes while the editor is open waits for it to end, then goes on Home as usual: here into
  /// Shelf's place, which Done freed.
  @Test
  func anAddRequestWhileEditingGoesIntoWhatDoneKeeps() async {
    let store = await addRequestWhileEditing()
    await store.send(.doneTapped) {
      $0.isEditing = false
      $0.draft = nil
      $0.$addRequests.withLock { $0 = [] }
      $0.$saved.withLock { $0?.placed[1] = Placement(widget: "tasks.list", size: .medium, column: 2, row: 0) }
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard", "tasks"] }
    }
  }

  /// After Cancel it goes into the layout from before, where Shelf still is.
  @Test
  func anAddRequestWhileEditingGoesIntoWhatCancelPutsBack() async {
    let store = await addRequestWhileEditing()
    await store.send(.cancelTapped) {
      $0.isEditing = false
      $0.draft = nil
      $0.$addRequests.withLock { $0 = [] }
      $0.$saved.withLock { $0?.placed.append(Placement(widget: "tasks.list", size: .medium, column: 2, row: 1)) }
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard", "shelf", "tasks"] }
    }
  }

  /// Tasks' page asks for its widget while the editor is open, with Shelf removed in the draft: nothing happens yet.
  func addRequestWhileEditing() async -> TestStoreOf<HomeFeature> {
    let saved = HomeLayout.initial([timer, clipboard, shelf])
    let store = makeStore(saved: saved, addRequests: ["tasks"])
    await store.send(.widgetsChanged([timer, clipboard, shelf, tasks])) {
      $0.widgets = [self.timer, self.clipboard, self.shelf, self.tasks]
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard", "shelf"] }
    }
    await store.send(.editTapped) {
      $0.isEditing = true
      $0.draft = saved
    }
    await store.send(.removeTapped("shelf.files")) {
      $0.draft?.placed.remove(at: 1)
    }
    await store.send(.addRequestsChanged(["tasks"]))
    return store
  }

  // MARK: - Add to Home, and what the shell hears back

  /// A feature's page asks for its first widget on Home: the notch row while it is free, or its first size that fits
  /// in the first free place. A request goes once taken.
  @Test
  func anAddRequestPutsTheFeaturesFirstWidget() async {
    let store = makeStore(saved: HomeLayout.initial([clipboard]), addRequests: ["shelf", "timer"])
    await store.send(.widgetsChanged([timer, clipboard, pinned, shelf])) {
      $0.widgets = [self.timer, self.clipboard, self.pinned, self.shelf]
      $0.$featuresOnHome.withLock { $0 = ["clipboard"] }
    }
    await store.send(.addRequestsChanged(["shelf", "timer"])) {
      $0.$saved.withLock { layout in
        layout?.placed.append(Placement(widget: "shelf.files", size: .medium, column: 2, row: 0))
        layout?.notchRow = "timer.timer"
      }
      $0.$addRequests.withLock { $0 = [] }
      $0.$featuresOnHome.withLock { $0 = ["clipboard", "shelf", "timer"] }
    }
  }

  /// A request takes the first of the widget's sizes that fits: Clipboard's history goes 2×1 when no 2×2 place is free.
  @Test
  func anAddRequestTakesTheFirstSizeThatFits() async {
    let wide = HomeLayout(notchRow: nil, placed: [Placement(widget: "shelf.files", size: .wide, column: 0, row: 0)])
    let store = makeStore(saved: wide, addRequests: ["clipboard"])
    await store.send(.widgetsChanged([clipboard, shelf])) {
      $0.widgets = [self.clipboard, self.shelf]
      $0.$featuresOnHome.withLock { $0 = ["shelf"] }
    }
    await store.send(.addRequestsChanged(["clipboard"])) {
      $0.$saved.withLock { $0?.placed.append(Placement(widget: "clipboard.history", size: .medium, column: 0, row: 1)) }
      $0.$addRequests.withLock { $0 = [] }
      $0.$featuresOnHome.withLock { $0 = ["shelf", "clipboard"] }
    }
  }

  /// Without room a request goes all the same, and Home stays as it is.
  @Test
  func anAddRequestWithoutRoomOnlyGoes() async {
    let store = makeStore(saved: fullGrid, addRequests: ["clipboard"])
    await store.send(.widgetsChanged([timer, clipboard, pinned, shelf])) {
      $0.widgets = [self.timer, self.clipboard, self.pinned, self.shelf]
      $0.$featuresOnHome.withLock { $0 = ["timer", "shelf"] }
    }
    await store.send(.addRequestsChanged(["clipboard"])) {
      $0.$addRequests.withLock { $0 = [] }
    }
    #expect(store.state.saved == fullGrid)
  }

  /// The shell hears which features have a widget on Home, as it changes: their pages say "On Home". An edit counts
  /// once Done keeps it.
  @Test
  func featuresOnHomeFollowWhatIsKept() async {
    let saved = HomeLayout.initial([timer, clipboard, shelf])
    let store = makeStore(saved: saved)
    await store.send(.widgetsChanged([timer, clipboard, shelf])) {
      $0.widgets = [self.timer, self.clipboard, self.shelf]
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard", "shelf"] }
    }
    await store.send(.editTapped) {
      $0.isEditing = true
      $0.draft = saved
    }
    await store.send(.removeTapped("shelf.files")) {
      $0.draft?.placed.removeAll { $0.widget == "shelf.files" }
    }
    await store.send(.doneTapped) {
      $0.isEditing = false
      $0.$saved.withLock { $0?.placed.removeAll { $0.widget == "shelf.files" } }
      $0.draft = nil
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard"] }
    }
    // Clipboard goes: its widget is away.
    await store.send(.widgetsChanged([timer, shelf])) {
      $0.widgets = [self.timer, self.shelf]
      $0.$saved.withLock { $0?.placed[0].away = 1 }
      $0.$featuresOnHome.withLock { $0 = ["timer"] }
    }
  }

  /// At launch Home starts before the shell tells it which widgets run: it waits for that, so a widget that took the
  /// place of an away one keeps it across the relaunch.
  @Test
  func aRelaunchKeepsTheWidgetThatTookAPlace() async {
    var returning = Placement(widget: "clipboard.history", size: .large, column: 0, row: 0)
    returning.away = 1
    let shelfPlace = Placement(widget: "shelf.files", size: .medium, column: 0, row: 0)
    let store = makeStore(saved: HomeLayout(notchRow: nil, placed: [returning, shelfPlace]))
    let start = await store.send(.started)
    await store.receive(\.addRequestsChanged)
    // Once every feature has started, the shell tells the widgets that run.
    @Shared(.runningHomeWidgets) var running
    $running.withLock { $0 = [clipboard, shelf] }
    await store.receive(\.widgetsChanged) {
      $0.widgets = [self.clipboard, self.shelf]
      $0.$saved.withLock { $0?.placed = [shelfPlace] }
      $0.$featuresOnHome.withLock { $0 = ["shelf"] }
    }
    await store.send(.stopped)
    await start.finish()
  }

  /// From its start Home follows the running widgets the shell tells and the requests of features' pages, whether its
  /// tab shows or not.
  @Test
  func homeFollowsTheShellFromItsStart() async {
    @Shared(.runningHomeWidgets) var running
    $running.withLock { $0 = [timer, clipboard] }
    let store = makeStore(saved: HomeLayout.initial([timer, clipboard]))
    let start = await store.send(.started)
    await store.receive(\.widgetsChanged) {
      $0.widgets = [self.timer, self.clipboard]
      $0.$featuresOnHome.withLock { $0 = ["timer", "clipboard"] }
    }
    await store.receive(\.addRequestsChanged)
    $running.withLock { $0 = [timer, clipboard, shelf] }
    await store.receive(\.widgetsChanged) { $0.widgets = [self.timer, self.clipboard, self.shelf] }
    await store.send(.stopped)
    await start.finish()
  }
}
