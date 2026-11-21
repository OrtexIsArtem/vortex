import AppKit
import ComposableArchitecture
import SwiftUI
import Testing
import VortexCore

@testable import FeatureHome

/// Where the pointer hits Home's small controls: points over an area clicked through AppKit, as in the window, and what
/// each click sends. A target is at least 44 pt where its neighbours leave room, and no other control's target cuts
/// into it. Home sits in a panel off every display that never takes the front.
@MainActor
struct HomeTargetsTests {
  final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
  }

  /// What the clicks sent, by name.
  @MainActor
  final class Sent {
    var names: [String] = []
  }

  /// A control's target as the clicks found it.
  struct Target {
    /// Along the lines through its middle, clicked every point: where it starts and how far it goes.
    var frame: CGRect
    /// Every point clicked inside `frame` sent it: no hole, and no other control's target in it.
    var isSolid: Bool
  }

  let sent = Sent()

  var widgets: [HomeWidget] {
    [
      HomeWidget(id: "timer.timer", feature: "timer", title: "Timer", place: .notchRow, view: Color.gray),
      HomeWidget(id: "clipboard.history", feature: "clipboard", title: "History", place: .grid([.large, .medium]), view: Color.gray),
      HomeWidget(id: "shelf.files", feature: "shelf", title: "Files", place: .grid([.large, .medium, .wide]), view: Color.gray),
    ]
  }

  var infos: [HomeWidgetInfo] {
    widgets.map { widget in
      HomeWidgetInfo(
        id: widget.id, feature: widget.feature, place: widget.place, name: String(localized: widget.title),
        featureName: String(widget.feature.capitalized), featureSymbol: "square"
      )
    }
  }

  /// Timer in the notch row and Clipboard's history 2×2 on the left; Shelf is off Home, with room.
  var layout: HomeLayout {
    HomeLayout(notchRow: "timer.timer", placed: [Placement(widget: "clipboard.history", size: .large, column: 0, row: 0)])
  }

  /// What an action is called here; nil for what the pointer's moves send rather than its clicks, and for the notch the
  /// view tells as it shows.
  static func name(_ action: HomeFeature.Action) -> String? {
    switch action {
    case .hovered, .notchChanged: nil
    case let .buttonDropped(point): "button \(Int(point.x)) \(Int(point.y))"
    case let .sizeTapped(id, size): "size \(id) \(size.rawValue)"
    case let .addTapped(id): "add \(id)"
    case let .featureTapped(id): "feature \(id)"
    case let .searchChanged(text): "search \(text)"
    default: "\(action)"
    }
  }

  /// The utilities dock as the shell gives it: two buttons, whose clicks are noted.
  func dock(isOpen: Bool, buttons: [UtilitiesDockButton]? = nil) -> UtilitiesDock {
    let sent = sent
    return UtilitiesDock(
      buttons: buttons ?? [
        UtilitiesDockButton(id: "keyboard.lock", symbol: "keyboard", label: "Lock Keyboard", warning: .accessibility),
        UtilitiesDockButton(id: "screentext.copy", symbol: "text.viewfinder", label: "Copy Text", keys: "⌃⌥T"),
      ],
      isOpen: isOpen,
      toggle: { sent.names.append("dock toggle") },
      close: { sent.names.append("dock close") },
      run: { sent.names.append("run \($0)") }
    )
  }

  /// Home as the window shows it, in a panel of its own: the store only notes what the controls send. Without a
  /// `cutout`, as under the menu bar icon, the window is the regular 680 pt. `widgets` stand in for the usual ones.
  func show(
    _ state: HomeFeature.State, width: CGFloat, dock: UtilitiesDock? = nil, cutout: CGRect? = nil,
    widgets: [HomeWidget]? = nil
  ) async throws -> Panel {
    let sent = sent
    let store = Store(initialState: state) {
      Reduce<HomeFeature.State, HomeFeature.Action> { _, action in
        if let name = Self.name(action) { sent.names.append(name) }
        return .none
      }
    }
    let size = CGSize(width: width, height: WindowSize.regular.size.height)
    let panel = Panel(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.contentView = NSHostingView(
      rootView: HomeView(store: store)
        .environment(\.homeWidgets, widgets ?? self.widgets)
        .environment(\.isWindowOpen, true)
        .environment(\.windowRequest) { _ in }
        .environment(\.showCatalog) { sent.names.append("catalog") }
        .environment(\.utilitiesDock, dock)
        .environment(\.notchCutout, cutout)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    )
    panel.orderFrontRegardless()
    panel.makeKey()
    try await Task.sleep(for: .milliseconds(300))
    return panel
  }

  /// The editor with the panel on `panel`, as wide as the large window's tab: on a notch whose `cutout` widens the
  /// window, wider by as much.
  func showEditor(
    _ panel: HomeFeature.Panel, search: String = "", layout: HomeLayout? = nil, cutout: CGRect? = nil,
    dock: UtilitiesDock? = nil
  ) async throws -> Panel {
    let layout = layout ?? self.layout
    var state = HomeFeature.State()
    state.$saved.withLock { $0 = layout }
    state.widgets = infos
    state.isEditing = true
    state.draft = layout
    state.panel = panel
    state.search = search
    let width = WindowSize.large.size(notchWidth: cutout?.width).width - VortexMetrics.sidebarWidth
    return try await show(state, width: width, dock: dock, cutout: cutout)
  }

  /// A mouse event at `point`, from the top left corner of Home, as the window gets it.
  func mouse(_ type: NSEvent.EventType, at point: CGPoint, in panel: Panel) -> NSEvent? {
    NSEvent.mouseEvent(
      with: type, location: CGPoint(x: point.x, y: panel.frame.height - point.y), modifierFlags: [],
      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil, eventNumber: 0,
      clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
    )
  }

  /// A click at `point`, from the top left corner of Home: what it sent, by name.
  func click(_ panel: Panel, at point: CGPoint) -> String? {
    sent.names = []
    // The search field's text follows a press in a loop of its own, which waits for the system's mouse-up: its points
    // aren't clicked, as no button sits there.
    let location = CGPoint(x: point.x, y: panel.frame.height - point.y)
    if let view = panel.contentView?.hitTest(location), view is NSTextField || view is NSTextView { return nil }
    guard let down = mouse(.leftMouseDown, at: point, in: panel), let up = mouse(.leftMouseUp, at: point, in: panel)
    else { return nil }
    panel.sendEvent(down)
    panel.sendEvent(up)
    return sent.names.isEmpty ? nil : sent.names.joined(separator: "+")
  }

  /// A drag from `start` to `end`, from the top left corner of Home, in ten moves: what it sent, by name. The events go
  /// in one turn, so no other suite's window takes the keyboard halfway; SwiftUI ends the gesture on a later turn, so
  /// what it sends is waited for, two seconds at most.
  func drag(_ panel: Panel, from start: CGPoint, to end: CGPoint) async throws -> String? {
    sent.names = []
    let moves = (1...10).map { step in
      CGPoint(x: start.x + (end.x - start.x) * CGFloat(step) / 10, y: start.y + (end.y - start.y) * CGFloat(step) / 10)
    }
    let events = [mouse(.leftMouseDown, at: start, in: panel)]
      + moves.map { mouse(.leftMouseDragged, at: $0, in: panel) }
      + [mouse(.leftMouseUp, at: end, in: panel)]
    panel.makeKey()
    for event in events.compactMap(\.self) {
      panel.sendEvent(event)
    }
    for _ in 0..<40 where sent.names.isEmpty {
      try await Task.sleep(for: .milliseconds(50))
    }
    return sent.names.isEmpty ? nil : sent.names.joined(separator: "+")
  }

  /// What Home's right-click menu at `point` holds, by what each of its items sends; empty without a menu.
  func menu(_ panel: Panel, at point: CGPoint) -> [String] {
    guard let event = mouse(.rightMouseDown, at: point, in: panel),
          let view = panel.contentView?.hitTest(event.locationInWindow),
          let menu = view.menu(for: event)
    else { return [] }
    return menu.items.indices.compactMap { index in
      sent.names = []
      menu.performActionForItem(at: index)
      return sent.names.first
    }
  }

  /// The targets in `area`, each found by clicks every 12 pt, less than any of them is wide, then measured to the point
  /// along the lines through its middle. The main actor is given back between rows, so other suites wait less.
  func targets(in panel: Panel, _ area: CGRect) async -> [String: Target] {
    let step: CGFloat = 12
    var coarse: [String: [CGPoint]] = [:]
    for y in stride(from: area.minY + step / 2, to: area.maxY, by: step) {
      // Another suite's window may have taken the keyboard meanwhile.
      panel.makeKey()
      for x in stride(from: area.minX + step / 2, to: area.maxX, by: step) {
        let point = CGPoint(x: x, y: y)
        if let name = click(panel, at: point) { coarse[name, default: []].append(point) }
      }
      await Task.yield()
    }
    var targets: [String: Target] = [:]
    for (name, points) in coarse {
      panel.makeKey()
      let xs = points.map(\.x)
      let ys = points.map(\.y)
      let middle = CGPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
      // A point of its own nearest the middle, so a target with a hole in its middle is still measured from inside.
      let start = points.min { hypot($0.x - middle.x, $0.y - middle.y) < hypot($1.x - middle.x, $1.y - middle.y) }!
      // Clicks land in the middle of a whole point, as a mouse's do.
      let origin = CGPoint(x: start.x.rounded(.down) + 0.5, y: start.y.rounded(.down) + 0.5)
      let left = reach(panel, name, from: origin, along: CGVector(dx: -1, dy: 0))
      let right = reach(panel, name, from: origin, along: CGVector(dx: 1, dy: 0))
      let up = reach(panel, name, from: origin, along: CGVector(dx: 0, dy: -1))
      let down = reach(panel, name, from: origin, along: CGVector(dx: 0, dy: 1))
      let frame = CGRect(x: origin.x - left - 0.5, y: origin.y - up - 0.5, width: left + right + 1, height: up + down + 1)
      let inside = stride(from: frame.minY + 0.5, to: frame.maxY, by: step).flatMap { y in
        stride(from: frame.minX + 0.5, to: frame.maxX, by: step).map { CGPoint(x: $0, y: y) }
      }
      targets[name] = Target(frame: frame, isSolid: inside.allSatisfy { click(panel, at: $0) == name })
      await Task.yield()
    }
    return targets
  }

  /// How many whole points past `start` along `direction` the clicks still send `name`: in 8 pt strides while they do,
  /// then halving the last stride. A target is convex, so it holds every point up to its edge.
  func reach(_ panel: Panel, _ name: String, from start: CGPoint, along direction: CGVector) -> CGFloat {
    func sends(_ offset: CGFloat) -> Bool {
      click(panel, at: CGPoint(x: start.x + direction.dx * offset, y: start.y + direction.dy * offset)) == name
    }
    var inside: CGFloat = 0
    var outside: CGFloat = 8
    while outside < 400, sends(outside) {
      inside = outside
      outside += 8
    }
    while outside - inside > 1 {
      let middle = ((inside + outside) / 2).rounded(.down)
      if sends(middle) { inside = middle } else { outside = middle }
    }
    return inside
  }

  // MARK: - The editor's panel

  /// A widget's size chips and Add are 44 pt tall targets: Add takes from the preview above it, the chips from the
  /// room under them, and they share the gap between them. Side by side, the chips' targets meet halfway across their
  /// gaps. "‹ Widgets" is 44 pt tall too, clear of Cancel and Done.
  @Test
  func aWidgetsChipsAndAddAreTargetsOf44Pt() async throws {
    let panel = try await showEditor(.feature("shelf"))
    defer { panel.orderOut(nil) }
    let area = CGRect(x: HomeView.gridWidth, y: 0, width: HomeView.panelWidth, height: 300)
    let targets = await targets(in: panel, area)
    let back = try #require(targets["backTapped"])
    let add = try #require(targets["add shelf.files"])
    let chips = try ["large", "medium", "wide"].map { try #require(targets["size shelf.files \($0)"]) }
    let done = try #require(targets["doneTapped"])
    for (name, target) in [("‹ Widgets", back), ("Add", add)] + zip(["2×2", "2×1", "4×1"], chips).map({ ($0, $1) }) {
      #expect(target.frame.height >= 44, "\(name): \(target.frame)")
      #expect(target.isSolid, "\(name): \(target.frame)")
    }
    #expect(add.frame.width >= 44, "Add: \(add.frame)")
    // Add's target ends where the chips' start, halfway across the gap between their rows.
    #expect(add.frame.maxY <= chips[2].frame.minY, "Add: \(add.frame), 4×1: \(chips[2].frame)")
    for (left, right) in zip(chips, chips.dropFirst()) {
      #expect(right.frame.minX - left.frame.maxX <= 1, "\(left.frame) and \(right.frame) leave a gap")
    }
    #expect(back.frame.minY >= done.frame.maxY, "‹ Widgets: \(back.frame), Done: \(done.frame)")
  }

  /// Without room the card says so under the chips, and the chips' targets reach over its words all the same.
  @Test
  func aWidgetWithoutRoomKeepsItsChips44PtTall() async throws {
    // Clipboard's history in the middle columns: no place two cells wide is left for Shelf.
    let middle = HomeLayout(notchRow: "timer.timer", placed: [Placement(widget: "clipboard.history", size: .large, column: 1, row: 0)])
    let panel = try await showEditor(.feature("shelf"), layout: middle)
    defer { panel.orderOut(nil) }
    let targets = await targets(in: panel, CGRect(x: HomeView.gridWidth, y: 200, width: HomeView.panelWidth, height: 140))
    for size in ["large", "medium", "wide"] {
      let chip = try #require(targets["size shelf.files \(size)"])
      #expect(chip.frame.height >= 44 && chip.isSolid, "\(size): \(chip.frame)")
    }
  }

  /// "More widgets in Features" is a 44 pt tall target above the panel's bottom edge; the search field's clear button
  /// takes the field's trailing end and the room around it, up to Done's capsule and down to the list.
  @Test
  func theLinkAndTheSearchClearButtonAreLargeTargets() async throws {
    let panel = try await showEditor(.features, search: "s")
    defer { panel.orderOut(nil) }
    let top = await targets(in: panel, CGRect(x: HomeView.gridWidth, y: 0, width: HomeView.panelWidth, height: 100))
    let bottom = await targets(in: panel, CGRect(x: HomeView.gridWidth, y: 370, width: HomeView.panelWidth, height: 70))
    let clear = try #require(top["search "])
    let done = try #require(top["doneTapped"])
    let link = try #require(bottom["doneTapped+catalog"])
    #expect(link.frame.height >= 44, "More widgets in Features: \(link.frame)")
    #expect(link.isSolid, "More widgets in Features: \(link.frame)")
    #expect(clear.frame.height >= 42, "Clear: \(clear.frame)")
    #expect(clear.frame.width >= 39, "Clear: \(clear.frame)")
    #expect(clear.isSolid, "Clear: \(clear.frame)")
    #expect(clear.frame.minY >= done.frame.maxY, "Clear: \(clear.frame), Done: \(done.frame)")
  }

  // MARK: - The utilities button and its strip

  /// Home with the timer in the notch row and Clipboard's history on the grid, outside the editor.
  var home: HomeFeature.State {
    var state = HomeFeature.State()
    state.$saved.withLock { $0 = layout }
    state.widgets = infos
    return state
  }

  /// The button at the notch row's right end is a 44 pt target, the row's whole height less 4 pt above and below, and
  /// its last 44 pt; with utilities it toggles the strip, without them it is the pencil, Edit Home itself.
  @Test
  func theUtilitiesButtonIsA44PtTargetAtTheRowsRightEndAndThePencilWithoutUtilities() async throws {
    for (dock, name) in [(dock(isOpen: false), "dock toggle"), (dock(isOpen: false, buttons: []), "editTapped")] {
      let panel = try await show(home, width: HomeView.gridWidth, dock: dock)
      defer { panel.orderOut(nil) }
      let area = CGRect(x: HomeView.gridWidth - 60, y: 0, width: 60, height: VortexMetrics.headerHeight)
      let targets = await targets(in: panel, area)
      let button = try #require(targets[name], "\(name): \(targets.keys.sorted())")
      #expect(button.frame.width >= 44 && button.frame.height >= 44 && button.isSolid, "\(name): \(button.frame)")
      #expect(button.frame.maxX <= HomeView.gridWidth && button.frame.minX >= HomeView.gridWidth - UtilitiesButton.slot)
    }
  }

  /// Without the shell, as in a preview, the button is the pencil too.
  @Test
  func withoutTheShellTheButtonIsThePencil() {
    #expect(UtilitiesButton.Mode(nil) == .pencil)
    #expect(UtilitiesButton.Mode(dock(isOpen: false, buttons: [])) == .pencil)
    #expect(UtilitiesButton.Mode(dock(isOpen: false)) == .utilities)
  }

  /// The open strip holds the buttons in one column, in the dock's order, each a 44 pt target, then, set apart, the
  /// pencil; a click anywhere else on Home puts the strip away.
  @Test
  func theStripsButtonsAre44PtTargetsInOrderWithThePencilLast() async throws {
    let panel = try await show(home, width: HomeView.gridWidth + HomeView.dockWidth, dock: dock(isOpen: true))
    defer { panel.orderOut(nil) }
    let strip = CGRect(x: HomeView.gridWidth, y: 0, width: HomeView.dockWidth, height: 200)
    let targets = await targets(in: panel, strip)
    let lock = try #require(targets["run keyboard.lock"])
    let copy = try #require(targets["run screentext.copy"])
    let pencil = try #require(targets["editTapped"])
    for (name, target) in [("lock", lock), ("copy", copy), ("pencil", pencil)] {
      #expect(target.frame.width >= 44 && target.frame.height >= 44 && target.isSolid, "\(name): \(target.frame)")
    }
    #expect(lock.frame.maxY <= copy.frame.minY && copy.frame.maxY < pencil.frame.minY)
    // The first sits beside the notch row's button, the column going down from there.
    #expect(lock.frame.minY >= 0 && lock.frame.maxY <= VortexMetrics.headerHeight)
    #expect(click(panel, at: CGPoint(x: 200, y: 200)) == "dock close")
    #expect(click(panel, at: CGPoint(x: HomeView.gridWidth - 22, y: 26)) == "dock close")
  }

  // MARK: - The button moved

  /// Over the middle of Clipboard's 2×2 card at the grid's left: (157, 240) from the top left of Home's column.
  let overClipboard = CGPoint(x: 157 - 312, y: 240)

  /// Moved over a widget, the button takes the clicks of its 44 pt target there, and right past it the widget's control
  /// gets its own: Clipboard's card, its face a button here.
  @Test
  func theMovedButtonTakesItsTargetsClicksAndTheWidgetTheRest() async throws {
    let sent = sent
    let card = HomeWidget(
      id: "clipboard.history", feature: "clipboard", title: "History", place: .grid([.large, .medium]),
      view: Button { sent.names.append("card") } label: { Color.gray.contentShape(Rectangle()) }.buttonStyle(.plain)
    )
    let state = home
    state.$saved.withLock { $0?.button = overClipboard }
    let widgets = self.widgets.map { $0.id == card.id ? card : $0 }
    let panel = try await show(state, width: HomeView.gridWidth, dock: dock(isOpen: false), widgets: widgets)
    defer { panel.orderOut(nil) }
    let targets = await targets(in: panel, CGRect(x: 107, y: 190, width: 100, height: 100))
    let button = try #require(targets["dock toggle"], "\(targets.keys.sorted())")
    #expect(button.frame.width >= 44 && button.frame.height >= 44 && button.isSolid, "\(button.frame)")
    #expect(abs(button.frame.midX - 157) <= 1 && abs(button.frame.midY - 240) <= 1, "\(button.frame)")
    for point in [CGPoint(x: 133, y: 240), CGPoint(x: 181, y: 240), CGPoint(x: 157, y: 216), CGPoint(x: 157, y: 264)] {
      #expect(click(panel, at: point) == "card", "\(point)")
    }
  }

  /// In the editor the button is there, in its slot or moved, the pencil or the utilities: a drag on it drops it where
  /// it ends. A click on it opens nothing.
  @Test
  func inTheEditorAClickOnTheButtonOpensNothing() async throws {
    for place in [nil, overClipboard] {
      var layout = self.layout
      layout.button = place
      let center = HomeLayout.buttonCenter(place, notch: nil)
      for utilities in [nil, dock(isOpen: false)] {
        let panel = try await showEditor(.features, layout: layout, dock: utilities)
        defer { panel.orderOut(nil) }
        let end = CGPoint(x: center.x - 100, y: center.y + 60)
        #expect(try await drag(panel, from: center, to: end) == "button \(Int(end.x)) \(Int(end.y))", "\(center)")
        #expect(click(panel, at: center) == nil, "\(center)")
      }
    }
  }

  /// While Home has no layout yet, the button in the editor stays in its slot: a drag on it moves nothing.
  @Test
  func beforeHomeHasALayoutTheEditorCantDragTheButton() async throws {
    var state = HomeFeature.State()
    state.widgets = infos
    state.isEditing = true
    let panel = try await show(state, width: WindowSize.large.size.width - VortexMetrics.sidebarWidth)
    defer { panel.orderOut(nil) }
    let slot = HomeLayout.buttonCenter(nil, notch: nil)
    #expect(try await drag(panel, from: slot, to: CGPoint(x: slot.x - 100, y: slot.y + 60)) == nil)
  }

  /// Outside the editor a right-click on the button shows Home's menu, Edit Home, in its slot and moved.
  @Test
  func rightClickingTheButtonShowsHomesMenu() async throws {
    for place in [nil, overClipboard] {
      let state = home
      state.$saved.withLock { $0?.button = place }
      let panel = try await show(state, width: HomeView.gridWidth, dock: dock(isOpen: false))
      defer { panel.orderOut(nil) }
      let center = HomeLayout.buttonCenter(place, notch: nil)
      #expect(menu(panel, at: center) == ["editTapped"], "\(center)")
    }
  }

  /// The strip's first button lines up with the moved button, with one utility or two; near Home's bottom the column
  /// moves up only as far as it needs to stay inside the window. A click on the moved button puts the strip away, as a
  /// click anywhere else on Home does.
  @Test
  func theStripLinesUpWithTheMovedButton() async throws {
    let lock = UtilitiesDockButton(id: "keyboard.lock", symbol: "keyboard", label: "Lock Keyboard")
    let copy = UtilitiesDockButton(id: "screentext.copy", symbol: "text.viewfinder", label: "Copy Text")
    for buttons in [[lock], [lock, copy]] {
      // The column: the buttons and the pencil, 44 pt each, and the 13 pt line between them.
      let column = CGFloat(buttons.count + 1) * 44 + 13
      for (y, top) in [(CGFloat(200), CGFloat(178)), (418, 440 - column)] {
        let state = home
        state.$saved.withLock { $0?.button = CGPoint(x: overClipboard.x, y: y) }
        let width = HomeView.gridWidth + HomeView.dockWidth
        let panel = try await show(state, width: width, dock: dock(isOpen: true, buttons: buttons))
        defer { panel.orderOut(nil) }
        let strip = CGRect(x: HomeView.gridWidth, y: 0, width: HomeView.dockWidth, height: 440)
        let targets = await targets(in: panel, strip)
        let first = try #require(targets["run keyboard.lock"])
        let pencil = try #require(targets["editTapped"])
        #expect(first.frame.minY == top, "\(buttons.count) at \(y): \(first.frame)")
        #expect(pencil.frame.maxY <= 440, "\(buttons.count) at \(y): \(pencil.frame)")
        #expect(click(panel, at: CGPoint(x: 157, y: y)) == "dock close")
      }
    }
  }

  // MARK: - A wide notch

  /// On a wide notch the window is wider, and Home with it: the notch row spans the tab, the utilities button still at
  /// its right end; the grid keeps its size in the middle, the extra room as equal margins at its sides, so what sits in
  /// the grid moves right by one of them. In the editor the panel starts where the regular window ends.
  @Test
  func onAWideNotchTheGridKeepsItsSizeInTheMiddle() async throws {
    let notch: CGFloat = 240
    let window = WindowSize.regular.size(notchWidth: notch).width
    let width = HomeView.width(notchWidth: notch)
    let margin = (width - HomeView.gridWidth) / 2
    #expect(width == window - VortexMetrics.sidebarWidth && margin == 27)
    let cutout = CGRect(x: (window - notch) / 2 - VortexMetrics.sidebarWidth, y: 0, width: notch, height: 32)

    let home = try await show(home, width: width, dock: dock(isOpen: false), cutout: cutout)
    let row = await targets(in: home, CGRect(x: width - 60, y: 0, width: 60, height: VortexMetrics.headerHeight))
    home.orderOut(nil)
    let button = try #require(row["dock toggle"], "\(row.keys.sorted())")
    #expect(button.frame.minX >= width - UtilitiesButton.slot && button.frame.maxX <= width, "\(button.frame)")

    // Clipboard's card, 2×2 at the grid's left, its face a button here, without a notch and on this one.
    let sent = sent
    let card = HomeWidget(
      id: "clipboard.history", feature: "clipboard", title: "History", place: .grid([.large, .medium]),
      view: Button { sent.names.append("card") } label: { Color.gray.contentShape(Rectangle()) }.buttonStyle(.plain)
    )
    func cardFace(_ cutout: CGRect?) async throws -> CGRect {
      let width = HomeView.width(notchWidth: cutout?.width)
      let widgets = self.widgets.map { $0.id == card.id ? card : $0 }
      let panel = try await show(self.home, width: width, dock: dock(isOpen: false), cutout: cutout, widgets: widgets)
      defer { panel.orderOut(nil) }
      let targets = await targets(in: panel, CGRect(x: 0, y: VortexMetrics.headerHeight, width: width / 2, height: 60))
      return try #require(targets["card"], "\(targets.keys.sorted())").frame
    }
    let plain = try await cardFace(nil)
    let wide = try await cardFace(cutout)
    #expect(wide.minX - plain.minX == margin && wide.size == plain.size, "without a notch \(plain), on \(notch) pt \(wide)")

    // The editor's Done, at the top of its panel.
    func done(_ cutout: CGRect?) async throws -> CGRect {
      let editor = try await showEditor(.features, cutout: cutout)
      defer { editor.orderOut(nil) }
      let regular = HomeView.width(notchWidth: cutout?.width)
      let targets = await targets(in: editor, CGRect(x: regular, y: 0, width: HomeView.panelWidth, height: 60))
      return try #require(targets["doneTapped"], "\(targets.keys.sorted())").frame
    }
    let plainDone = try await done(nil)
    let wideDone = try await done(cutout)
    #expect(wideDone.minX - plainDone.minX == width - HomeView.gridWidth, "Done: \(plainDone), \(wideDone)")
  }

  // MARK: - No capsule

  /// Home's bottom right corner holds no button of its own: the grid is free to its edge, and a click there sends
  /// nothing where no widget lies.
  @Test
  func theGridsBottomRightCornerHoldsNoButton() async throws {
    let panel = try await show(home, width: HomeView.gridWidth, dock: dock(isOpen: false))
    defer { panel.orderOut(nil) }
    let height = WindowSize.regular.size.height
    let targets = await targets(in: panel, CGRect(x: HomeView.gridWidth - 120, y: height - 70, width: 120, height: 70))
    #expect(targets.isEmpty, "\(targets.keys.sorted())")
  }

  /// With the timer in the notch row and nothing on the grid, the grid still has its Edit Home button in its middle,
  /// as an empty Home does: something on the grid starts the editor.
  @Test
  func anEmptyGridUnderARowWidgetKeepsItsEditHomeButton() async throws {
    var state = HomeFeature.State()
    state.$saved.withLock { $0 = HomeLayout(notchRow: "timer.timer", placed: []) }
    state.widgets = infos
    let panel = try await show(state, width: HomeView.gridWidth, dock: dock(isOpen: false))
    defer { panel.orderOut(nil) }
    let grid = CGRect(x: 0, y: VortexMetrics.headerHeight, width: HomeView.gridWidth, height: 300)
    let targets = await targets(in: panel, grid)
    #expect(targets.keys.sorted() == ["editTapped"])
    let edit = try #require(targets["editTapped"])
    #expect(edit.frame.height >= 30 && edit.frame.midY > VortexMetrics.headerHeight + 100, "Edit Home: \(edit.frame)")
  }

  /// With no widget on Home, its own Edit Home button stays in the middle of the grid, a quiet capsule.
  @Test
  func anEmptyHomeKeepsItsEditHomeButton() async throws {
    var state = HomeFeature.State()
    state.$saved.withLock { $0 = HomeLayout(notchRow: nil, placed: []) }
    state.widgets = infos
    let panel = try await show(state, width: HomeView.gridWidth, dock: dock(isOpen: false))
    defer { panel.orderOut(nil) }
    let grid = CGRect(x: 0, y: VortexMetrics.headerHeight, width: HomeView.gridWidth, height: 300)
    let targets = await targets(in: panel, grid)
    #expect(targets.keys.sorted() == ["editTapped"])
    let edit = try #require(targets["editTapped"])
    #expect(edit.frame.height >= 30 && edit.frame.midY > VortexMetrics.headerHeight + 100, "Edit Home: \(edit.frame)")
  }
}
