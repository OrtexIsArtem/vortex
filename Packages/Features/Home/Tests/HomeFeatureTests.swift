import ComposableArchitecture
import Testing
import VortexCore

@testable import FeatureHome

/// Home's layout as it lives on: saved in home.json, through features that go and come back.
@MainActor
struct HomeFeatureTests {
  func info(_ id: String, _ place: HomeWidgetPlace) -> WidgetInfo {
    let feature = String(id.split(separator: ".")[0])
    return WidgetInfo(id: id, feature: feature, place: place, name: id, featureName: feature, featureSymbol: "square")
  }

  var timer: WidgetInfo { info("timer.timer", .notchRow) }
  var clipboard: WidgetInfo { info("clipboard.history", .grid([.large, .medium])) }
  var shelf: WidgetInfo { info("shelf.files", .grid([.medium, .wide])) }
  var tasks: WidgetInfo { info("tasks.list", .grid([.medium])) }

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
}
