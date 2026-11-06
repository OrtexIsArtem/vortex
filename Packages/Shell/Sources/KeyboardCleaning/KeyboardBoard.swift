import CoreGraphics
import VortexPlatform

/// The keyboard the lock screen draws: a MacBook's, with the website's English (US) labels, never translated. ANSI,
/// also for JIS keyboards, or ISO: § top left, a key left of Z, a narrower left Shift and a tall Return. Each row is 15
/// units wide; a unit key is as wide as the others in every row, as on the real keyboard.
struct KeyboardBoard: Equatable {
  /// A drawn key, placed in the board's own coordinates.
  struct Cap: Equatable, Identifiable {
    enum Shape: Equatable {
      case key
      /// The oval of the Touch ID (power) button: no press washes it, and pressing it locks the Mac.
      case touchID
      /// ISO's Return, over two rows: `frame` covers both; below `upperHeight` it is `lowerWidth` wide, flush right.
      case tallReturn(lowerWidth: CGFloat, upperHeight: CGFloat)
    }

    var label: String
    /// Nil only for Touch ID.
    var key: KeyboardKey?
    var frame: CGRect
    var shape = Shape.key
    /// The function row: shorter keys, smaller labels.
    var isShort = false

    var id: String { key.map { "\($0)" } ?? "touchID" }
  }

  /// Sizes in points: a row's height, the space between keys and around them.
  struct Metrics: Equatable {
    var width: CGFloat
    var keyHeight: CGFloat = 34
    var shortHeight: CGFloat = 21
    var gap: CGFloat = 5
    var padding: CGFloat = 12
  }

  let caps: [Cap]
  let size: CGSize
  let metrics: Metrics

  init(_ layout: KeyboardLayout, metrics: Metrics) {
    let pitch = (metrics.width - 2 * metrics.padding + metrics.gap) / Self.rowUnits
    var caps: [Cap] = []
    var y = metrics.padding
    for (index, row) in (layout == .iso ? Self.isoRows : Self.ansiRows).enumerated() {
      let isShort = index == 0
      let height = isShort ? metrics.shortHeight : metrics.keyHeight
      // ← ↑ ↓ →: half as tall.
      let half = (height - Self.halfGap) / 2
      var x = metrics.padding
      for slot in row {
        let width = slot.units * pitch - metrics.gap
        func add(
          _ label: String, _ key: KeyboardKey?, top: CGFloat = 0, height: CGFloat = height, shape: Cap.Shape = .key
        ) {
          let frame = CGRect(x: x, y: y + top, width: width, height: height)
          caps.append(Cap(label: label, key: key, frame: frame, shape: shape, isShort: isShort))
        }
        switch slot {
        case let .key(label, key, _):
          add(label, key)
        case .touchID:
          add("", nil, shape: .touchID)
        case let .lowerHalf(label, key):
          add(label, key, top: height - half, height: half)
        case let .pair(upper, lower):
          add(upper.label, upper.key, height: half)
          add(lower.label, lower.key, top: height - half, height: half)
        case let .tallReturn(_, lowerUnits):
          let shape = Cap.Shape.tallReturn(lowerWidth: lowerUnits * pitch - metrics.gap, upperHeight: height)
          add("return", .return, height: 2 * height + metrics.gap, shape: shape)
        case .room:
          break
        }
        x += slot.units * pitch
      }
      y += height + metrics.gap
    }
    self.caps = caps
    self.size = CGSize(width: metrics.width, height: y - metrics.gap + metrics.padding)
    self.metrics = metrics
  }

  // MARK: - Rows

  static let rowUnits: CGFloat = 15
  /// Between ↑ and ↓, the half-height arrows.
  static let halfGap: CGFloat = 3

  enum Slot: Equatable {
    case key(String, KeyboardKey, units: CGFloat = 1)
    case touchID(units: CGFloat)
    /// ← and →: the lower half of a unit.
    case lowerHalf(String, KeyboardKey)
    /// ↑ over ↓ in one unit.
    case pair(upper: Labeled, lower: Labeled)
    /// ISO's Return: `units` wide on its row, `lowerUnits` on the next, flush right.
    case tallReturn(units: CGFloat, lowerUnits: CGFloat)
    /// Where the tall Return comes down into the row below.
    case room(units: CGFloat)

    struct Labeled: Equatable {
      var label: String
      var key: KeyboardKey
    }

    var units: CGFloat {
      switch self {
      case let .key(_, _, units), let .touchID(units), let .tallReturn(units, _), let .room(units): units
      case .lowerHalf, .pair: 1
      }
    }
  }

  private static func letters(_ keys: [KeyboardKey]) -> [Slot] {
    keys.map { .key("\($0)", $0) }
  }

  private static let functionRow: [Slot] = [.key("esc", .escape, units: 1.5)]
    + zip(1...12, [KeyboardKey.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]).map { .key("F\($0)", $1) }
    + [.touchID(units: 1.5)]

  private static let digits: [Slot] = zip(
    "1234567890",
    [KeyboardKey.digit1, .digit2, .digit3, .digit4, .digit5, .digit6, .digit7, .digit8, .digit9, .digit0]
  ).map { .key(String($0), $1) } + [.key("-", .minus), .key("=", .equal), .key("delete", .delete, units: 2)]

  private static let topLetters: [Slot] = [.key("tab", .tab, units: 1.5)]
    + letters([.q, .w, .e, .r, .t, .y, .u, .i, .o, .p]) + [.key("[", .leftBracket), .key("]", .rightBracket)]

  private static let homeLetters: [Slot] = [.key("⇪", .capsLock, units: 1.75)]
    + letters([.a, .s, .d, .f, .g, .h, .j, .k, .l]) + [.key(";", .semicolon), .key("'", .quote)]

  private static let bottomLetters = letters([.z, .x, .c, .v, .b, .n, .m])
    + [.key(",", .comma), .key(".", .period), .key("/", .slash), .key("⇧", .rightShift, units: 2.75)]

  private static let spaceRow: [Slot] = [
    .key("fn", .fn), .key("⌃", .control), .key("⌥", .leftOption), .key("⌘", .leftCommand, units: 1.25),
    .key("", .space, units: 5.5), .key("⌘", .rightCommand, units: 1.25), .key("⌥", .rightOption),
    .lowerHalf("←", .leftArrow),
    .pair(upper: Slot.Labeled(label: "↑", key: .upArrow), lower: Slot.Labeled(label: "↓", key: .downArrow)),
    .lowerHalf("→", .rightArrow),
  ]

  static let ansiRows: [[Slot]] = [
    functionRow,
    [.key("`", .grave)] + digits,
    topLetters + [.key("\\", .backslash, units: 1.5)],
    homeLetters + [.key("return", .return, units: 2.25)],
    [.key("⇧", .leftShift, units: 2.25)] + bottomLetters,
    spaceRow,
  ]

  static let isoRows: [[Slot]] = [
    functionRow,
    [.key("§", .section)] + digits,
    topLetters + [.tallReturn(units: 1.5, lowerUnits: 1.25)],
    homeLetters + [.key("\\", .backslash), .room(units: 1.25)],
    [.key("⇧", .leftShift, units: 1.25), .key("`", .grave)] + bottomLetters,
    spaceRow,
  ]
}
