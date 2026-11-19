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

  /// What an action is called here; nil for what the pointer's moves send rather than its clicks.
  static func name(_ action: HomeFeature.Action) -> String? {
    switch action {
    case .hovered: nil
    case let .sizeTapped(id, size): "size \(id) \(size.rawValue)"
    case let .addTapped(id): "add \(id)"
    case let .featureTapped(id): "feature \(id)"
    case let .searchChanged(text): "search \(text)"
    default: "\(action)"
    }
  }

  /// Home as the window shows it, in a panel of its own: the store only notes what the controls send.
  func show(_ state: HomeFeature.State, width: CGFloat) async throws -> Panel {
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
        .environment(\.homeWidgets, widgets)
        .environment(\.isWindowOpen, true)
        .environment(\.windowRequest) { _ in }
        .environment(\.showCatalog) { sent.names.append("catalog") }
        .environment(\.keyboardCleaning) { sent.names.append("keyboard") }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    )
    panel.orderFrontRegardless()
    panel.makeKey()
    try await Task.sleep(for: .milliseconds(300))
    return panel
  }

  /// The editor with the panel on `panel`, as wide as the large window's tab.
  func showEditor(_ panel: HomeFeature.Panel, search: String = "", layout: HomeLayout? = nil) async throws -> Panel {
    let layout = layout ?? self.layout
    var state = HomeFeature.State()
    state.$saved.withLock { $0 = layout }
    state.widgets = infos
    state.isEditing = true
    state.draft = layout
    state.panel = panel
    state.search = search
    return try await show(state, width: HomeView.gridWidth + HomeView.panelWidth)
  }

  /// A click at `point`, from the top left corner of Home: what it sent, by name.
  func click(_ panel: Panel, at point: CGPoint) -> String? {
    sent.names = []
    let location = CGPoint(x: point.x, y: panel.frame.height - point.y)
    func event(_ type: NSEvent.EventType) -> NSEvent? {
      NSEvent.mouseEvent(
        with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
        pressure: type == .leftMouseDown ? 1 : 0
      )
    }
    // The search field's text follows a press in a loop of its own, which waits for the system's mouse-up: its points
    // aren't clicked, as no button sits there.
    if let view = panel.contentView?.hitTest(location), view is NSTextField || view is NSTextView { return nil }
    guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return nil }
    panel.sendEvent(down)
    panel.sendEvent(up)
    return sent.names.isEmpty ? nil : sent.names.joined(separator: "+")
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

  // MARK: - The corner buttons

  /// The pencil is a 44 pt target and the keyboard button 44 pt tall, each up to the capsule's top and left edges,
  /// where a widget may lie behind it, and past its bottom into the margin under the grid; the pencil past its right
  /// edge too.
  @Test
  func theCornerButtonsAre44PtTallTargetsInsideTheCapsule() async throws {
    var state = HomeFeature.State()
    state.$saved.withLock { $0 = layout }
    state.widgets = infos
    let panel = try await show(state, width: HomeView.gridWidth)
    defer { panel.orderOut(nil) }
    let height = WindowSize.regular.size.height
    let targets = await targets(in: panel, CGRect(x: HomeView.gridWidth - 120, y: height - 70, width: 120, height: 70))
    let pencil = try #require(targets["editTapped"])
    let keyboard = try #require(targets["keyboard"])
    // The capsule: two 36 pt buttons 2 pt apart, in 2 pt of capsule, 40 pt tall, 12 pt from Home's corner.
    let capsule = CGRect(x: HomeView.gridWidth - 12 - 78, y: height - 12 - 40, width: 78, height: 40)
    #expect(pencil.frame.width >= 44 && pencil.frame.height >= 44, "pencil: \(pencil.frame)")
    #expect(keyboard.frame.height >= 44, "keyboard: \(keyboard.frame)")
    for (name, target) in [("pencil", pencil), ("keyboard", keyboard)] {
      #expect(target.isSolid, "\(name): \(target.frame)")
      #expect(target.frame.minY >= capsule.minY && target.frame.minX >= capsule.minX, "\(name): \(target.frame)")
    }
    #expect(pencil.frame.minX >= keyboard.frame.maxX, "pencil: \(pencil.frame), keyboard: \(keyboard.frame)")
  }
}
