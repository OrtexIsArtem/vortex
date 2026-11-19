import CoreGraphics
import Testing
import VortexPlatform

@testable import FeatureKeyboardCleaning

/// The drawn keyboard: every key of the board has a key code of its own.
struct KeyboardBoardTests {
  /// The lock screen's: the window less its margins.
  static let metrics = KeyboardBoard.Metrics(width: 624)

  @Test(arguments: KeyboardLayout.allCases)
  func everyDrawnKeyButTouchIDHasAKeyCodeOfItsOwn(layout: KeyboardLayout) {
    let board = KeyboardBoard(layout, metrics: Self.metrics)
    let keys = board.caps.compactMap(\.key)
    #expect(Set(keys).count == keys.count)
    #expect(board.caps.filter { $0.key == nil }.map(\.shape) == [.touchID])
    #expect(Set(board.caps.map(\.id)).count == board.caps.count)
  }

  /// ANSI, also for JIS, draws every key but §; ISO draws them all, § top left and ` left of Z.
  @Test
  func ansiDrawsEveryKeyButTheSectionAndISOThemAll() throws {
    let ansi = KeyboardBoard(.ansi, metrics: Self.metrics)
    #expect(Set(ansi.caps.compactMap(\.key)) == Set(KeyboardKey.allCases).subtracting([.section]))
    #expect(KeyboardBoard(.jis, metrics: Self.metrics) == ansi)
    let iso = KeyboardBoard(.iso, metrics: Self.metrics)
    #expect(Set(iso.caps.compactMap(\.key)) == Set(KeyboardKey.allCases))

    func frame(_ key: KeyboardKey, on board: KeyboardBoard) throws -> CGRect {
      try #require(board.caps.first { $0.key == key }).frame
    }
    // Top left of the digits: ` on ANSI, § on ISO, where ` sits left of Z.
    let (ansiGrave, ansiDigit1) = try (frame(.grave, on: ansi), frame(.digit1, on: ansi))
    let (section, grave, z) = try (frame(.section, on: iso), frame(.grave, on: iso), frame(.z, on: iso))
    let (shift, ansiShift) = try (frame(.leftShift, on: iso), frame(.leftShift, on: ansi))
    #expect(ansiGrave.minY == ansiDigit1.minY)
    #expect(section == ansiGrave)
    #expect(grave.minY == z.minY && grave.maxX < z.minX)
    #expect(shift.width < ansiShift.width)
    // ISO's Return comes down over the home row, right of \.
    let tall = try #require(iso.caps.first { $0.key == .return })
    let (p, l, backslash) = try (frame(.p, on: iso), frame(.l, on: iso), frame(.backslash, on: iso))
    #expect(tall.frame.minY == p.minY && tall.frame.maxY == l.maxY)
    #expect(backslash.minY == l.minY)
    guard case let .tallReturn(lowerWidth, _) = tall.shape else {
      Issue.record("ISO's Return is not tall")
      return
    }
    #expect(tall.frame.maxX - lowerWidth > backslash.maxX)
  }

  /// Every row is 15 units and fills the board from edge to edge, keys never overlap, and the function row is the
  /// short one, as on a MacBook.
  @Test(arguments: [KeyboardLayout.ansi, .iso])
  func rowsFillTheBoardAndKeysNeverOverlap(layout: KeyboardLayout) {
    let rows = layout == .iso ? KeyboardBoard.isoRows : KeyboardBoard.ansiRows
    #expect(rows.map { $0.map(\.units).reduce(0, +) } == Array(repeating: KeyboardBoard.rowUnits, count: 6))
    let board = KeyboardBoard(layout, metrics: Self.metrics)
    let metrics = Self.metrics
    var top = metrics.padding
    for height in [metrics.shortHeight] + Array(repeating: metrics.keyHeight, count: 5) {
      let row = board.caps.filter { $0.frame.intersects(CGRect(x: 0, y: top, width: board.size.width, height: height)) }
      #expect(abs((row.map(\.frame.minX).min() ?? 0) - metrics.padding) < 0.01)
      #expect(abs((row.map(\.frame.maxX).max() ?? 0) - (board.size.width - metrics.padding)) < 0.01)
      top += height + metrics.gap
    }
    #expect(abs(top - metrics.gap + metrics.padding - board.size.height) < 0.01)
    let parts = board.caps.flatMap { cap -> [CGRect] in
      guard case let .tallReturn(lowerWidth, upperHeight) = cap.shape else { return [cap.frame] }
      let (upper, lower) = cap.frame.divided(atDistance: upperHeight, from: .minYEdge)
      return [upper, CGRect(x: cap.frame.maxX - lowerWidth, y: lower.minY, width: lowerWidth, height: lower.height)]
    }
    for (index, part) in parts.enumerated() {
      for other in parts[(index + 1)...] {
        #expect(!part.insetBy(dx: 0.01, dy: 0.01).intersects(other))
      }
    }
    #expect(board.caps.filter(\.isShort).map(\.label) == ["esc"] + (1...12).map { "F\($0)" } + [""])
  }
}
