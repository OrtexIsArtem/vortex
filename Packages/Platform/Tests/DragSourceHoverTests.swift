import AppKit
import Observation
import SwiftUI
import Testing

@testable import VortexPlatform

/// What a `DragSourceArea` reports as the pointer comes, goes, and the views move under it, and how the controls its
/// hover shows take clicks. The rows sit in a panel off every display that never takes the front; enter and exit come
/// straight to the view, as AppKit sends them, and the pointer is where the panel says a test put it.
@MainActor
struct DragSourceHoverTests {
  final class Panel: NSPanel {
    /// Where the pointer is, in the panel: off it until a test puts it somewhere.
    var pointer = NSPoint(x: -1_000, y: -1_000)
    override var canBecomeKey: Bool { true }
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
  }

  @MainActor
  @Observable
  final class Rows {
    var order = ["a", "b", "c"]
    /// Each row's hover as its area reported it, in order.
    @ObservationIgnored var hovers: [String] = []
    @ObservationIgnored var clicks: [String] = []
  }

  /// Rows 34 pt tall, one under another; the hovered one shows a button at its end, as a clipboard row its eye.
  struct RowsView: View {
    let rows: Rows

    var body: some View {
      VStack(spacing: 0) {
        ForEach(rows.order, id: \.self) { id in
          Row(id: id, rows: rows)
        }
        Spacer(minLength: 0)
      }
      .frame(width: 300, height: 200)
    }
  }

  struct Row: View {
    let id: String
    let rows: Rows
    @State private var isHovered = false

    var body: some View {
      Color.clear
        .frame(height: 34)
        .overlay {
          DragSourceArea(
            items: { [] },
            onClick: { _ in rows.clicks.append("row \(id)") },
            onHover: { isHovered in
              self.isHovered = isHovered
              rows.hovers.append("\(id) \(isHovered ? "in" : "out")")
            }
          )
        }
        .overlay(alignment: .trailing) {
          if isHovered {
            Button {
              rows.clicks.append("button \(id)")
            } label: {
              Color.clear
                .frame(width: 44, height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
    }
  }

  let rows = Rows()

  /// The rows in a panel, and each row's area by its id.
  func show() async throws -> (Panel, [String: DragSourceView]) {
    _ = NSApplication.shared
    let panel = Panel(
      contentRect: CGRect(x: -20_000, y: -20_000, width: 300, height: 200),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.contentView = NSHostingView(rootView: RowsView(rows: rows))
    panel.orderFrontRegardless()
    panel.makeKey()
    // Every row laid out, each in a place of its own.
    _ = try await eventually { Set(areas(in: panel.contentView ?? NSView()).map { $0.convert($0.bounds, to: nil).maxY }).count == 3 }
    var views: [String: DragSourceView] = [:]
    for view in areas(in: try #require(panel.contentView)) {
      // From the top: "a", "b", "c".
      let place = Int((200 - view.convert(view.bounds, to: nil).maxY) / 34)
      views[rows.order[place]] = view
    }
    return (panel, views)
  }

  func areas(in view: NSView) -> [DragSourceView] {
    (view as? DragSourceView).map { [$0] } ?? view.subviews.flatMap { areas(in: $0) }
  }

  /// Gives the main actor back while AppKit and SwiftUI finish what changed, and the areas look at the pointer.
  func settle() async throws {
    try await Task.sleep(for: .milliseconds(300))
  }

  /// Gives the main actor back until `condition` holds, or five seconds pass: other suites may hold it meanwhile.
  func eventually(_ condition: () -> Bool) async throws -> Bool {
    let start = ContinuousClock.now
    while !condition(), ContinuousClock.now - start < .seconds(5) {
      try await Task.sleep(for: .milliseconds(20))
    }
    return condition()
  }

  func pointer(_ type: NSEvent.EventType, in window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.enterExitEvent(
      with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
    ))
  }

  /// A press and a release, as AppKit hands them to the window.
  func click(_ window: NSWindow, at location: CGPoint) {
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
      if let event = NSEvent.mouseEvent(
        with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
      ) {
        window.sendEvent(event)
      }
    }
  }

  /// The middle of a row's button, in the window: the row's end.
  func buttonPoint(of view: DragSourceView) -> CGPoint {
    let frame = view.convert(view.bounds, to: nil)
    return CGPoint(x: frame.maxX - 12, y: frame.midY)
  }

  /// The pointer rests over the row at this place from the top.
  func putPointer(onRow place: Int, in panel: Panel) {
    panel.pointer = CGPoint(x: 150, y: 200 - CGFloat(place) * 34 - 17)
  }

  /// A click that waited behind the pointer's coming, as when the main thread was busy, finds the button the hover
  /// shows already there: the row's own click never takes it.
  @Test
  func aClickThatCameWithTheHoverReachesTheButtonTheHoverShows() async throws {
    let (panel, views) = try await show()
    defer { panel.orderOut(nil) }
    let row = try #require(views["b"])
    putPointer(onRow: 1, in: panel)
    // The pointer comes and clicks in one turn of the run loop: nothing is drawn between.
    row.mouseEntered(with: try pointer(.mouseEntered, in: panel))
    click(panel, at: buttonPoint(of: row))
    #expect(rows.clicks == ["button b"])
  }

  /// AppKit's enter and exit are reported as they come, as before: a parent that lets one row hold the hover at a time
  /// hears the pointer come back to a row whose leaving it never heard.
  @Test
  func appKitsEnterAndExitAreReportedAsTheyCome() async throws {
    let (panel, views) = try await show()
    defer { panel.orderOut(nil) }
    let row = try #require(views["a"])
    putPointer(onRow: 0, in: panel)
    rows.hovers = []
    row.mouseEntered(with: try pointer(.mouseEntered, in: panel))
    row.mouseEntered(with: try pointer(.mouseEntered, in: panel))
    row.mouseExited(with: try pointer(.mouseExited, in: panel))
    #expect(rows.hovers == ["a in", "a in", "a out"])
  }

  /// AppKit tells a view that moves away from a still pointer nothing, nor one that moves under it. The area looks
  /// where the pointer is once the move is laid out: the row that left loses its hover, the one now under the pointer
  /// gets it, and the button shows there only.
  @Test
  func theHoverFollowsThePointerWhenTheRowsMoveUnderIt() async throws {
    let (panel, views) = try await show()
    defer { panel.orderOut(nil) }
    let a = try #require(views["a"])
    let b = try #require(views["b"])
    putPointer(onRow: 1, in: panel)
    b.mouseEntered(with: try pointer(.mouseEntered, in: panel))
    try await settle()
    rows.hovers = []
    // "b" goes to the top, as a copied item; "a" slides under the pointer.
    rows.order = ["b", "a", "c"]
    #expect(try await eventually { Set(rows.hovers) == ["b out", "a in"] })
    rows.clicks = []
    click(panel, at: buttonPoint(of: a))
    click(panel, at: buttonPoint(of: b))
    #expect(rows.clicks == ["button a", "row b"])
  }

  /// A row that moves away loses its hover even where nothing comes under the pointer: a row shown in the window now
  /// gets the hover when it comes under the pointer, as AppKit's own enter would never say.
  @Test
  func aRowThatMovesAwayLosesItsHoverAndOneThatComesGetsIt() async throws {
    let (panel, views) = try await show()
    defer { panel.orderOut(nil) }
    let c = try #require(views["c"])
    putPointer(onRow: 2, in: panel)
    c.mouseEntered(with: try pointer(.mouseEntered, in: panel))
    try await settle()
    rows.hovers = []
    rows.order = ["c", "a"]
    // "b" went from the window; nothing is under the pointer now.
    #expect(try await eventually { rows.hovers == ["c out"] })
    rows.order = ["c", "a", "b"]
    #expect(try await eventually { rows.hovers == ["c out", "b in"] })
  }
}
