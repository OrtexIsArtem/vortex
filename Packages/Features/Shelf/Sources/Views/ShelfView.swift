import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The shelf tab: what the user put aside, ready to be dragged into any app.
public struct ShelfView: View {
  let store: StoreOf<ShelfFeature>
  @State private var isTargeted = false
  @FocusState private var isFocused: Bool

  public init(store: StoreOf<ShelfFeature>) {
    self.store = store
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      if store.items.isEmpty {
        EmptyShelf(
          isTargeted: isTargeted,
          watchedFolders: store.settings.watchedFolders.map(\.folder)
        ) {
          store.send(.chooseFolderTapped)
        }
      } else {
        ScrollView {
          TimelineView(.everyMinute) { timeline in
            LazyVGrid(
              columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 4),
              spacing: 14
            ) {
              ForEach(store.items) { item in
                ShelfTile(
                  item: item,
                  info: store.info[item.id],
                  isSelected: store.selection.contains(item.id),
                  isFresh: store.fresh.contains(item.id),
                  isUnavailable: store.unavailable.contains(item.id),
                  now: timeline.date,
                  dragItems: { store.state.dragItems(startingAt: item.id) }
                ) { action in
                  isFocused = true
                  store.send(action, animation: .snappy(duration: 0.25))
                }
              }
              DropTile(isTargeted: isTargeted)
            }
          }
          .padding(.leading, 10)
          .padding(.trailing, 18)
          .padding(.top, 4)
          .padding(.bottom, 16)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .contentShape(Rectangle())
          .onTapGesture { store.send(.backgroundClicked) }
        }
        .scrollIndicators(.never)
        .overlay {
          // With files on the shelf, the whole tab still takes drops: outline it while something hovers.
          if isTargeted {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .strokeBorder(VortexColor.accent, lineWidth: 1.5)
              .padding(.leading, 4)
              .padding(.trailing, 12)
              .padding(.bottom, 10)
              .allowsHitTesting(false)
          }
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
      }
    }
    .dropTarget(isTargeted: $isTargeted) { items in
      store.send(.dropped(items), animation: .snappy(duration: 0.25))
    }
    .focusable()
    .focusEffectDisabled()
    .focused($isFocused)
    .onKeyPress(.space) {
      store.send(.quickLookPressed)
      return .handled
    }
    .onKeyPress(keys: [.delete, .deleteForward]) { _ in
      store.send(.removeSelectedPressed, animation: .snappy(duration: 0.25))
      return .handled
    }
    .onKeyPress(characters: ["a"]) { press in
      guard press.modifiers.contains(.command) else { return .ignored }
      store.send(.selectAllPressed)
      return .handled
    }
    .modifier(ShelfSeenTracking(store: store) { isFocused = true })
  }

  private var header: some View {
    HStack(spacing: 6) {
      Text("Shelf", bundle: .module)
        .font(.system(size: 13, weight: .semibold))
      if !store.items.isEmpty {
        Text(store.items.count, format: .number)
          .font(.system(size: 13).monospacedDigit())
          .foregroundStyle(VortexColor.tertiaryText)
      }
      Spacer()
      if store.items.contains(where: { !$0.isPinned }) {
        Button {
          store.send(.clearTapped, animation: .snappy(duration: 0.25))
        } label: {
          Text("Clear", bundle: .module)
        }
        .buttonStyle(.quietCapsule)
        .help(Text("Takes everything off the shelf except pinned items", bundle: .module))
      }
    }
    .frame(height: VortexMetrics.headerHeight)
    .padding(.leading, 10)
    .padding(.trailing, 18)
  }
}

/// The whole tab is a drop zone while the shelf is empty; it also offers to watch a folder for new builds.
private struct EmptyShelf: View {
  let isTargeted: Bool
  let watchedFolders: [URL]
  let watchFolder: () -> Void

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "arrow.down.to.line")
        .font(.system(size: 20))
        .foregroundStyle(isTargeted ? VortexColor.primaryText : VortexColor.tertiaryText)
        .padding(.bottom, 4)
      Group {
        if isTargeted {
          Text("Release to put it on the shelf", bundle: .module)
        } else {
          Text("Drop files here", bundle: .module)
        }
      }
      .font(.system(size: 13, weight: .medium))
      // No word of the menu bar icon: on macOS 26 a drop on it never reaches Vortex, and the icon may be hidden.
      Text("Unpinned items leave the shelf after 24 hours.", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
      if !watchedFolders.isEmpty {
        Text("New files from \(watchedFolders.map(\.lastPathComponent).formatted(.list(type: .and))) appear here by themselves.", bundle: .module)
          .font(.system(size: 11.5))
          .foregroundStyle(VortexColor.tertiaryText)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 360)
      }
      Button(action: watchFolder) {
        Text("Watch a folder…", bundle: .module)
      }
      .buttonStyle(.quietCapsule)
      .padding(.top, 10)
      .help(Text("New files in it land on the shelf by themselves, for example builds", bundle: .module))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(
          isTargeted ? VortexColor.accent : VortexColor.dropOutline,
          style: StrokeStyle(lineWidth: isTargeted ? 1.5 : 1, dash: isTargeted ? [] : [5, 4])
        )
    }
    .padding(.leading, 10)
    .padding(.trailing, 18)
    .padding(.bottom, 16)
    .animation(.easeOut(duration: 0.15), value: isTargeted)
  }
}

/// The last tile of the grid: a reminder that more can be dropped.
struct DropTile: View {
  let isTargeted: Bool
  var height: CGFloat = 100

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "arrow.down.to.line")
        .font(.system(size: 14, weight: .medium))
      Text("Drop here", bundle: .module)
        .font(.system(size: 11.5))
    }
    .foregroundStyle(isTargeted ? VortexColor.primaryText : VortexColor.tertiaryText)
    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
    .background {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(
          isTargeted ? VortexColor.accent : VortexColor.dropOutline,
          style: StrokeStyle(lineWidth: isTargeted ? 1.5 : 1, dash: isTargeted ? [] : [5, 4])
        )
    }
    .animation(.easeOut(duration: 0.15), value: isTargeted)
    .accessibilityHidden(true)
  }
}
