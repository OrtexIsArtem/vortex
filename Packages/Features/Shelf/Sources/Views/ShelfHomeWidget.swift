import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The shelf on Home: its files as small tiles to drag out, and a place to drop more.
struct ShelfHomeWidget: View {
  let store: StoreOf<ShelfFeature>
  @State private var isTargeted = false

  static let width: CGFloat = 352
  /// How far the selection ring of a tile reaches beyond it.
  private static let ringRoom: CGFloat = 3

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Text("Shelf", bundle: .module)
        if !store.items.isEmpty {
          Text(store.items.count, format: .number)
            .foregroundStyle(VortexColor.tertiaryText)
        }
      }
      .font(.system(size: 12).monospacedDigit())
      .foregroundStyle(VortexColor.secondaryText)
      .frame(height: 18)

      ScrollView {
        TimelineView(.everyMinute) { timeline in
          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4),
            spacing: 10
          ) {
            ForEach(store.items) { item in
              ShelfTile(
                item: item,
                info: store.info[item.id],
                isSelected: store.selection.contains(item.id),
                isFresh: store.fresh.contains(item.id),
                isUnavailable: store.unavailable.contains(item.id),
                now: timeline.date,
                isCompact: true,
                dragItems: { store.state.dragItems(startingAt: item.id) }
              ) { action in
                store.send(action, animation: .snappy(duration: 0.25))
              }
            }
            DropTile(isTargeted: isTargeted, height: 72)
          }
          // The ring of a selected tile sits 3 pt outside it and a scroll view clips what lies outside: the grid
          // gets that room here and the scroll view takes it back below, so the tiles stay where they are.
          .padding([.top, .horizontal], Self.ringRoom)
        }
      }
      .scrollIndicators(.never)
      .padding([.top, .horizontal], -Self.ringRoom)
    }
    .frame(width: Self.width)
    .frame(maxHeight: .infinity, alignment: .top)
    .dropTarget(isTargeted: $isTargeted) { items in
      store.send(.dropped(items), animation: .snappy(duration: 0.25))
    }
    // Seeing the shelf on Home counts as seeing the shelf: fresh marks and the flash count start over afterwards.
    .modifier(ShelfSeenTracking(store: store))
  }
}
