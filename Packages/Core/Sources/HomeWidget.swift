import SwiftUI

/// The sizes a widget takes on Home's grid of 4×2 cells. The window by the notch is 680×440 on every Mac, so the sizes
/// are exact points, as for widgets on an iPhone.
public enum HomeWidgetSize: String, CaseIterable, Codable, Sendable {
  /// 1×1, 143×182.
  case small
  /// 2×1, 298×182.
  case medium
  /// 4×1, 608×182.
  case wide
  /// 2×2, 298×376.
  case large
  /// 4×2, 608×376: the whole grid.
  case full

  public var columns: Int {
    switch self {
    case .small: 1
    case .medium, .large: 2
    case .wide, .full: 4
    }
  }

  public var rows: Int {
    switch self {
    case .small, .medium, .wide: 1
    case .large, .full: 2
    }
  }

  /// The widget's size on screen, its cells and the gaps between them.
  public var points: CGSize {
    CGSize(
      width: CGFloat(columns) * HomeGrid.cell.width + CGFloat(columns - 1) * HomeGrid.gap,
      height: CGFloat(rows) * HomeGrid.cell.height + CGFloat(rows - 1) * HomeGrid.gap
    )
  }

  /// "2×1": columns by rows.
  public var label: String { "\(columns)×\(rows)" }
}

/// The grid under Home's notch row: 4×2 cells of 143×182 pt, 12 pt apart, 8 pt from the sides and 12 pt from the
/// bottom of the window.
public enum HomeGrid {
  public static let columns = 4
  public static let rows = 2
  public static let cell = CGSize(width: 143, height: 182)
  public static let gap: CGFloat = 12
  public static let sideInset: CGFloat = 8
  public static let bottomInset: CGFloat = 12

  /// Where a widget of `size` whose top left cell is `column`, `row` sits, in the area under the notch row: the tab's
  /// own width, the sidebar not counted.
  public static func frame(column: Int, row: Int, size: HomeWidgetSize) -> CGRect {
    CGRect(
      origin: CGPoint(x: sideInset + CGFloat(column) * (cell.width + gap), y: CGFloat(row) * (cell.height + gap)),
      size: size.points
    )
  }
}

/// Where a widget goes on Home: the row next to the notch, or the grid in one of its sizes, in order of preference.
public enum HomeWidgetPlace: Equatable, Sendable {
  case notchRow
  case grid([HomeWidgetSize])
}

/// One of a feature's widgets on Home. A feature offers one or two (`FeatureModule.makeHomeWidgets()`); the shell
/// collects them from running features and hands them to Home in `homeWidgets`, and Home never knows the features
/// themselves. The view reads its size from `homeWidgetSize`.
public struct HomeWidget: Identifiable {
  /// `<feature id>.<name>`, which Home keeps in its layout.
  public let id: String
  public let feature: FeatureID
  /// The widget's name in the editor, such as "History".
  public let title: LocalizedStringResource
  public let place: HomeWidgetPlace
  public let view: AnyView
  /// The feature's name and symbol for the editor; the shell fills them from the feature's description.
  public var featureTitle: LocalizedStringResource
  public var featureSymbol: String

  @MainActor
  public init(id: String, feature: FeatureID, title: LocalizedStringResource, place: HomeWidgetPlace, view: some View) {
    self.id = id
    self.feature = feature
    self.title = title
    self.place = place
    self.view = AnyView(view)
    featureTitle = title
    featureSymbol = "square.grid.2x2"
  }

  /// What's wrong with a feature's widgets, empty when nothing is: at most two widgets, ids `<feature>.<name>` and
  /// each once, 1–3 different grid sizes.
  public static func problems(_ widgets: [HomeWidget], feature: FeatureID) -> [String] {
    var problems: [String] = []
    if widgets.count > 2 { problems.append("\(feature) offers \(widgets.count) widgets; at most 2") }
    var ids: Set<String> = []
    for widget in widgets {
      if !widget.id.hasPrefix("\(feature).") || widget.id.count <= feature.count + 1 {
        problems.append("\(widget.id) doesn't start with \(feature).")
      }
      if !ids.insert(widget.id).inserted { problems.append("\(widget.id) is there twice") }
      if case let .grid(sizes) = widget.place {
        if !(1...3).contains(sizes.count) { problems.append("\(widget.id) has \(sizes.count) sizes; 1–3") }
        if Set(sizes).count != sizes.count { problems.append("\(widget.id) names a size twice") }
      }
    }
    return problems
  }
}

extension EnvironmentValues {
  /// Widgets of the running features, in sidebar order, for Home.
  @Entry public var homeWidgets: [HomeWidget] = []
  /// The size Home lays this widget out at; nil in the row next to the notch.
  @Entry public var homeWidgetSize: HomeWidgetSize? = nil
  /// Turns on keyboard cleaning, which the shell runs: every key held back, the window kept open on its lock screen
  /// until the user turns the keyboard back on. Nil where nobody offers it, and Home shows no button for it.
  @Entry public var keyboardCleaning: (@MainActor () -> Void)? = nil
}
