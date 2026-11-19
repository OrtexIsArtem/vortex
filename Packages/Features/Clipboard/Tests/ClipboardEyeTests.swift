import AppKit
import ComposableArchitecture
import SwiftUI
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureClipboard

/// The eye at the end of a Home row, and a card's eye, pin and ×, clicked through AppKit as in the window: each does
/// only what it says, also when the click came with the pointer, before the row or card was drawn again; the eye shows
/// on one row at most, the one under the pointer; eye and buttons follow the pointer when a copy moves the rows or
/// cards, and go when the window closes. The widget and the tab sit in panels off every display that never take the
/// front; the pointer is where a test puts it, and AppKit's enter comes straight to the row or card.
@MainActor
struct ClipboardEyeTests {
  final class Panel: NSPanel {
    /// Where the pointer is, in the panel: off it until a test puts it somewhere.
    var pointer = NSPoint(x: -1_000, y: -1_000)
    override var canBecomeKey: Bool { true }
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
  }

  /// What the clicks sent, by name; the store does nothing else, but a copy takes its item to the top, as the
  /// reducer's does.
  @MainActor
  final class Sent {
    var names: [String] = []
    /// `.tabShown` and `.tabHidden`, as the window opens and closes.
    var visibility: [String] = []
  }

  let sent = Sent()

  /// Texts "0" to "4", newest first.
  let items = (0..<5).map { index in
    ClipboardItem(
      id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!, content: .text("\(index)"), source: nil,
      copiedAt: Date(timeIntervalSinceReferenceDate: 800_000_000 - Double(index)), fingerprint: "text:\(index)"
    )
  }

  static func name(_ action: ClipboardFeature.Action) -> String? {
    func text(_ id: ClipboardItem.ID) -> String { String(id.uuidString.last!) }
    switch action {
    case let .itemTapped(id): return "copy \(text(id))"
    case let .quickLookTapped(id): return "quickLook \(text(id))"
    case let .pinTapped(id): return "pin \(text(id))"
    case let .deleteTapped(id): return "delete \(text(id))"
    default: return nil
    }
  }

  func store() -> StoreOf<ClipboardFeature> {
    var state = ClipboardFeature.State()
    state.items = IdentifiedArray(uniqueElements: items)
    state.isLoaded = true
    let sent = sent
    return Store(initialState: state) {
      Reduce<ClipboardFeature.State, ClipboardFeature.Action> { state, action in
        if let name = Self.name(action) { sent.names.append(name) }
        if case .tabShown = action { sent.visibility.append("shown") }
        if case .tabHidden = action { sent.visibility.append("hidden") }
        if case let .itemTapped(id) = action, var item = state.items.remove(id: id) {
          item.copiedAt = Date(timeIntervalSinceReferenceDate: 900_000_000)
          state.items.insert(item, at: 0)
        }
        return .none
      }
    }
  }

  func show(_ view: some View, size: CGSize) async throws -> Panel {
    _ = NSApplication.shared
    let panel = Panel(
      contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.contentView = NSHostingView(
      rootView: view.environment(\.isWindowOpen, true).frame(width: size.width, height: size.height)
    )
    panel.orderFrontRegardless()
    panel.makeKey()
    // Every row or card laid out, each in a place of its own.
    _ = try await eventually { Set(allAreas(in: panel.contentView).map { "\(frame(of: $0).origin)" }).count == items.count }
    return panel
  }

  /// Gives the main actor back while AppKit and SwiftUI finish what changed.
  func settle() async throws {
    try await Task.sleep(for: .milliseconds(300))
  }

  /// Gives the main actor back until `condition` holds, or five seconds pass: other suites may hold it meanwhile. Then
  /// once more, so what the change set off (an area's look at the pointer) is done too.
  func eventually(_ condition: () -> Bool) async throws -> Bool {
    let start = ContinuousClock.now
    while !condition(), ContinuousClock.now - start < .seconds(5) {
      try await Task.sleep(for: .milliseconds(20))
    }
    try await Task.sleep(for: .milliseconds(50))
    return condition()
  }

  func allAreas(in view: NSView?) -> [DragSourceView] {
    guard let view else { return [] }
    return (view as? DragSourceView).map { [$0] } ?? view.subviews.flatMap { allAreas(in: $0) }
  }

  /// The rows or cards, by the item each shows.
  func areas(in panel: Panel) throws -> [String: DragSourceView] {
    let views = allAreas(in: panel.contentView).sorted {
      let (a, b) = ($0.convert($0.bounds, to: nil), $1.convert($1.bounds, to: nil))
      return a.maxY == b.maxY ? a.minX < b.minX : a.maxY > b.maxY
    }
    try #require(views.count == items.count)
    // From the top, along each line: the items' order, "0" to "4".
    return Dictionary(uniqueKeysWithValues: views.enumerated().map { ("\($0.offset)", $0.element) })
  }

  func frame(of view: NSView) -> CGRect {
    view.convert(view.bounds, to: nil)
  }

  /// The pointer comes over the row or card: it rests at `point`, and AppKit's enter reaches the area.
  func enter(_ view: DragSourceView, at point: CGPoint, in panel: Panel) throws {
    panel.pointer = point
    view.mouseEntered(with: try #require(NSEvent.enterExitEvent(
      with: .mouseEntered, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: panel.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
    )))
  }

  /// A click at `point`: what it sent, by name.
  func click(_ panel: Panel, at point: CGPoint) -> [String] {
    sent.names = []
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      if let event = NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
      ) {
        panel.sendEvent(event)
      }
    }
    return sent.names
  }

  // MARK: - Home

  /// The widget at Large: 266×348 pt inside its card.
  func showWidget() async throws -> (Panel, [String: DragSourceView]) {
    let panel = try await show(ClipboardHomeWidget(store: store()), size: CGSize(width: 266, height: 348))
    return (panel, try areas(in: panel))
  }

  /// Where a row's eye is: at its end.
  func eye(of row: DragSourceView) -> CGPoint {
    CGPoint(x: frame(of: row).maxX - 12, y: frame(of: row).midY)
  }

  /// The middle of a row's text, left of its eye.
  func text(of row: DragSourceView) -> CGPoint {
    CGPoint(x: frame(of: row).midX - 40, y: frame(of: row).midY)
  }

  /// The eye shows Quick Look and nothing else: no copy, so nothing moves. A click that came with the pointer, before
  /// the row was drawn again, as while Quick Look opened for another row, finds the eye too.
  @Test
  func aClickOnARowsEyeOnlyShowsQuickLook() async throws {
    let (panel, rows) = try await showWidget()
    defer { panel.orderOut(nil) }
    let one = try #require(rows["1"])
    try enter(one, at: text(of: one), in: panel)
    try await settle()
    #expect(click(panel, at: eye(of: one)) == ["quickLook 1"])
    // The pointer comes over another row and clicks its eye in one turn of the run loop.
    let three = try #require(rows["3"])
    try enter(three, at: eye(of: three), in: panel)
    #expect(click(panel, at: eye(of: three)) == ["quickLook 3"])
  }

  /// One row shows its eye at a time, the one the pointer came to last, even when the pointer's leaving the row
  /// before went unheard, as when Quick Look's panel or the closing window covered it.
  @Test
  func anEyeShowsOnOneRowAtMost() async throws {
    let (panel, rows) = try await showWidget()
    defer { panel.orderOut(nil) }
    let one = try #require(rows["1"])
    let three = try #require(rows["3"])
    try enter(one, at: text(of: one), in: panel)
    try await settle()
    try enter(three, at: text(of: three), in: panel)
    try await settle()
    #expect(click(panel, at: eye(of: three)) == ["quickLook 3"])
    // Row 1 has no eye left: its end copies it.
    #expect(click(panel, at: eye(of: one)) == ["copy 1"])
  }

  /// A click on a row copies it, and the copy takes it to the top under a pointer that stays: the row now under the
  /// pointer shows the eye, and the copied row none.
  @Test
  func theEyeFollowsThePointerWhenACopyMovesTheRows() async throws {
    let (panel, rows) = try await showWidget()
    defer { panel.orderOut(nil) }
    let two = try #require(rows["2"])
    let one = try #require(rows["1"])
    let (top, under) = try (frame(of: #require(rows["0"])), frame(of: two))
    let place = text(of: two)
    try enter(two, at: place, in: panel)
    try await settle()
    #expect(click(panel, at: place) == ["copy 2"])
    // "2" goes first, and "1" slides under the pointer, once the rows have moved.
    #expect(try await eventually { frame(of: two) == top && frame(of: one) == under })
    #expect(click(panel, at: eye(of: one)) == ["quickLook 1"])
    #expect(click(panel, at: eye(of: two)) == ["copy 2"])
  }

  /// The eye goes when the window closes: open again, it shows only once the pointer comes to a row.
  @Test
  func theEyeGoesWithTheWindow() async throws {
    let isOpen = WindowState()
    let panel = try await show(
      OpenWindow(state: isOpen) { ClipboardHomeWidget(store: store()) },
      size: CGSize(width: 266, height: 348)
    )
    defer { panel.orderOut(nil) }
    let rows = try areas(in: panel)
    let one = try #require(rows["1"])
    try enter(one, at: text(of: one), in: panel)
    try await settle()
    // Closed with the pointer on the row, as Esc closes it, and opened again by hovering the notch.
    panel.pointer = NSPoint(x: -1_000, y: -1_000)
    sent.visibility = []
    isOpen.isOpen = false
    #expect(try await eventually { sent.visibility == ["hidden"] })
    isOpen.isOpen = true
    #expect(try await eventually { sent.visibility == ["hidden", "shown"] })
    #expect(click(panel, at: eye(of: one)) == ["copy 1"])
  }

  @MainActor
  @Observable
  final class WindowState {
    var isOpen = true
  }

  /// The window opening and closing around a view, as the shell's chrome sets `isWindowOpen`.
  struct OpenWindow<Content: View>: View {
    let state: WindowState
    @ViewBuilder let content: () -> Content

    var body: some View {
      content().environment(\.isWindowOpen, state.isOpen)
    }
  }

  // MARK: - The tab's cards

  func showTab() async throws -> (Panel, [String: DragSourceView]) {
    let panel = try await show(ClipboardView(store: store()), size: CGSize(width: 624, height: 440))
    return (panel, try areas(in: panel))
  }

  /// A card's buttons from its top right corner: ×, pin, eye; 30 pt each, 2 pt apart, 6 pt in.
  func button(_ name: String, of card: DragSourceView) -> CGPoint {
    let offset: CGFloat = switch name {
    case "delete": 21
    case "pin": 53
    default: 85
    }
    return CGPoint(x: frame(of: card).maxX - offset, y: frame(of: card).maxY - 21)
  }

  /// Each button does what it says, also when the click came with the pointer, before the card was drawn again: never a
  /// copy of the card under it.
  @Test
  func aCardsButtonsDoOnlyWhatTheySay() async throws {
    let (panel, cards) = try await showTab()
    defer { panel.orderOut(nil) }
    for (name, item) in [("delete", "2"), ("pin", "3"), ("eye", "4")] {
      let card = try #require(cards[item])
      // The pointer comes over the card and clicks in one turn of the run loop.
      try enter(card, at: button(name, of: card), in: panel)
      let expected = name == "eye" ? "quickLook \(item)" : "\(name) \(item)"
      #expect(click(panel, at: button(name, of: card)) == [expected], "\(name)")
    }
  }

  /// A card's buttons go when the window closes: open again, they show only once the pointer comes to a card.
  @Test
  func aCardsButtonsGoWithTheWindow() async throws {
    let isOpen = WindowState()
    let panel = try await show(
      OpenWindow(state: isOpen) { ClipboardView(store: store()) },
      size: CGSize(width: 624, height: 440)
    )
    defer { panel.orderOut(nil) }
    let card = try #require(try areas(in: panel)["1"])
    try enter(card, at: CGPoint(x: frame(of: card).midX, y: frame(of: card).midY - 20), in: panel)
    try await settle()
    panel.pointer = NSPoint(x: -1_000, y: -1_000)
    sent.visibility = []
    isOpen.isOpen = false
    #expect(try await eventually { sent.visibility == ["hidden"] })
    isOpen.isOpen = true
    #expect(try await eventually { sent.visibility == ["hidden", "shown"] })
    #expect(click(panel, at: button("delete", of: card)) == ["copy 1"])
  }

  /// A card a copy took to the top under a pointer that stays shows no buttons; the card now under the pointer does.
  @Test
  func aCardsButtonsFollowThePointerWhenACopyMovesTheCards() async throws {
    let (panel, cards) = try await showTab()
    defer { panel.orderOut(nil) }
    let two = try #require(cards["2"])
    let one = try #require(cards["1"])
    let (first, third) = try (frame(of: #require(cards["0"])), frame(of: two))
    let place = CGPoint(x: frame(of: two).midX, y: frame(of: two).midY - 20)
    try enter(two, at: place, in: panel)
    try await settle()
    #expect(click(panel, at: place) == ["copy 2"])
    // "2" goes first, and "1" moves to where "2" was, under the pointer, once the cards have moved.
    #expect(try await eventually { frame(of: two) == first && frame(of: one) == third })
    #expect(click(panel, at: button("delete", of: two)) == ["copy 2"])
    #expect(click(panel, at: button("delete", of: one)) == ["delete 1"])
  }
}
