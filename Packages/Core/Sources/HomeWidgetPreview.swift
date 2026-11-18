import SwiftUI

extension View {
  /// A widget's view as Home lays it out on its card: told its size (`homeWidgetSize`), inset 14 by 16 pt, on the card
  /// of the size's cells.
  public func homeWidgetCard(size: HomeWidgetSize) -> some View {
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    return environment(\.homeWidgetSize, size)
      .padding(.vertical, 14)
      .padding(.horizontal, 16)
      .frame(width: size.points.width, height: size.points.height, alignment: .topLeading)
      .background(shape.fill(VortexColor.dock))
      .clipShape(shape)
  }
}

/// For a widget's `#Preview`: Home as the window shows it, with every cell outlined and the widget at its real size on its
/// cells, or in the row next to the notch. Preview each size the widget offers: nothing else shows what spills over.
public struct HomeWidgetPreview: View {
  let widget: HomeWidget
  let size: HomeWidgetSize

  /// `size` is ignored for a widget of the notch row.
  public init(_ widget: HomeWidget, size: HomeWidgetSize) {
    self.widget = widget
    self.size = size
  }

  public var body: some View {
    let grid = HomeGrid.frame(column: 0, row: 0, size: .full)
    VStack(alignment: .leading, spacing: 0) {
      Group {
        if widget.place == .notchRow {
          widget.view
        } else {
          Color.clear
        }
      }
      .frame(height: VortexMetrics.headerHeight)
      ZStack(alignment: .topLeading) {
        ForEach(0..<HomeGrid.rows, id: \.self) { row in
          ForEach(0..<HomeGrid.columns, id: \.self) { column in
            let cell = HomeGrid.frame(column: column, row: row, size: .small)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .strokeBorder(VortexColor.dropOutline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
              .frame(width: cell.width, height: cell.height)
              .offset(x: cell.minX, y: cell.minY)
          }
        }
        if widget.place != .notchRow {
          let frame = HomeGrid.frame(column: 0, row: 0, size: size)
          widget.view
            .homeWidgetCard(size: size)
            .offset(x: frame.minX, y: frame.minY)
        }
      }
      // As wide as Home: the cards are placed by their offsets, not by the stack.
      .frame(maxWidth: .infinity, minHeight: grid.height + HomeGrid.bottomInset, alignment: .topLeading)
    }
    .frame(width: grid.maxX + HomeGrid.sideInset, alignment: .topLeading)
    .background(VortexColor.windowBackground)
    .foregroundStyle(VortexColor.primaryText)
  }
}
