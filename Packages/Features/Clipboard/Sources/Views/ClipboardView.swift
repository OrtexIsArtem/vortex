import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The clipboard tab: the history as a grid of cards. Click a card to copy it again, drag it into any app.
public struct ClipboardView: View {
  let store: StoreOf<ClipboardFeature>
  @Environment(\.isWindowOpen) private var isWindowOpen

  public init(store: StoreOf<ClipboardFeature>) {
    self.store = store
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("Clipboard", bundle: .module)
          .font(.system(size: 13, weight: .semibold))
        Spacer()
        if store.items.contains(where: { !$0.isPinned }) {
          Button {
            store.send(.clearTapped)
          } label: {
            Text("Clear", bundle: .module)
          }
          .buttonStyle(.quietCapsule)
          .help(Text("Removes everything except pinned items", bundle: .module))
        }
      }
      .frame(height: VortexMetrics.headerHeight)
      .padding(.leading, 10)
      .padding(.trailing, 18)

      if store.items.isEmpty {
        EmptyClipboard()
      } else {
        ScrollView {
          TimelineView(.everyMinute) { timeline in
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
              ForEach(store.items) { item in
                ClipboardCard(
                  item: item,
                  isUnavailable: store.unavailable.contains(item.id),
                  isRevealed: store.revealed.contains(item.id),
                  isJustCopied: store.justCopied == item.id,
                  now: timeline.date
                ) { action in
                  store.send(action, animation: .snappy(duration: 0.25))
                }
              }
            }
          }
          .padding(.leading, 10)
          .padding(.trailing, 18)
          .padding(.top, 4)
          .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
      }
    }
    .task(id: isWindowOpen) {
      if isWindowOpen { store.send(.tabShown) }
    }
  }
}

private struct EmptyClipboard: View {
  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "doc.on.clipboard")
        .font(.system(size: 20))
        .foregroundStyle(VortexColor.tertiaryText)
        .padding(.bottom, 4)
      Text("Nothing copied yet", bundle: .module)
        .font(.system(size: 13, weight: .medium))
      Text("Copy text, a link, an image or files, and it appears here.", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.bottom, VortexMetrics.headerHeight)
  }
}
