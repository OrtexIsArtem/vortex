import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The clipboard tab: search and Clear next to the notch, and the history as a grid of cards. Click a card to copy it
/// again, drag it into any app; its eye, or Space over it, shows it in Quick Look.
public struct ClipboardView: View {
  @Bindable var store: StoreOf<ClipboardFeature>
  @Environment(\.notchCutout) private var cutout
  @FocusState private var isSearchFocused: Bool
  /// The grid has the keyboard: Space shows the card under the pointer in Quick Look.
  @FocusState private var isGridFocused: Bool
  @State private var cardUnderPointer = CardUnderPointer()

  public init(store: StoreOf<ClipboardFeature>) {
    self.store = store
  }

  public var body: some View {
    let items = store.shownItems
    VStack(alignment: .leading, spacing: 0) {
      header
        .frame(height: VortexMetrics.headerHeight)
      if store.isSearching, store.searchResults != nil, items.isEmpty {
        Text("Nothing found", bundle: .module)
          .font(.system(size: 12.5))
          .foregroundStyle(VortexColor.tertiaryText)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(.bottom, VortexMetrics.headerHeight)
      } else if items.isEmpty {
        EmptyClipboard()
      } else {
        ScrollView {
          TimelineView(.everyMinute) { timeline in
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
              ForEach(items) { item in
                ClipboardCard(
                  item: item,
                  isUnavailable: store.unavailable.contains(item.id),
                  isRevealed: store.revealed.contains(item.id),
                  isJustCopied: store.justCopied == item.id,
                  wholeText: store.wholeText?.id == item.id ? store.wholeText?.text : nil,
                  now: timeline.date,
                  onHover: { isHovered in cardUnderPointer.hovered(item.id, isHovered) }
                ) { action in
                  store.send(action, animation: .snappy(duration: 0.25))
                }
                // Whether its files are still there is checked as it comes on screen, not for the whole history.
                .onAppear {
                  if !item.fileURLs.isEmpty { store.send(.cardAppeared(item.id)) }
                }
                .onDisappear { cardUnderPointer.hovered(item.id, false) }
              }
            }
          }
          .padding(.leading, 10)
          .padding(.trailing, 18)
          .padding(.top, 4)
          .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
        // Space as in Finder: Quick Look on the card under the pointer, and again to close it. The search field, which
        // takes a space as typed, is not in the grid.
        .focusable()
        .focusEffectDisabled()
        .focused($isGridFocused)
        .onKeyPress(.space, phases: .down) { _ in
          store.send(.spacePressed(over: cardUnderPointer.id))
          return .handled
        }
        // Held down, it toggles once; its repeats are taken without doing anything, as AppKit would beep at them.
        .onKeyPress(.space, phases: .repeat) { _ in .handled }
      }
      // Under the grid rather than over it, as in Tasks: laid over a scroll view, a toast doesn't get the click.
      if let pending = store.pendingRemoval {
        UndoToast(reason: pending.reason) { store.send(.undoTapped, animation: .snappy(duration: 0.22)) }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.snappy(duration: 0.22), value: store.pendingRemoval != nil)
    .background {
      // ⌘F goes to the search field; also under a Ukrainian or Russian layout, where the F key types «а» and a
      // shortcut doesn't fall back to the Latin key by itself.
      ForEach(["f", "а"], id: \.self) { key in
        Button {
          isSearchFocused = true
        } label: {
          EmptyView()
        }
        .keyboardShortcut(KeyEquivalent(Character(key)), modifiers: .command)
      }
      .opacity(0)
      .accessibilityHidden(true)
    }
    .modifier(
      ClipboardVisibilityTracking(store: store) {
        // Space works at once, unless the search field has the keyboard.
        if !isSearchFocused { isGridFocused = true }
      }
    )
  }

  /// The title left of the notch; search and Clear right of it, as in Tasks.
  @ViewBuilder
  private var header: some View {
    let title = Text("Clipboard", bundle: .module)
      .font(.system(size: 13, weight: .semibold))
      .padding(.leading, 10)
    let tools = HStack(spacing: 6) {
      SearchField(query: $store.query.sending(\.queryChanged), isFocused: $isSearchFocused)
      // Clear would clear what the search hides too.
      if !store.isSearching, store.items.contains(where: { !$0.isPinned }) {
        Button {
          store.send(.clearTapped, animation: .snappy(duration: 0.22))
        } label: {
          Text("Clear", bundle: .module)
        }
        .buttonStyle(.quietCapsule)
        .help(Text("Removes everything except pinned items", bundle: .module))
      }
    }
    if let cutout {
      HStack(spacing: 0) {
        title
          .frame(width: max(cutout.minX - 12, 0), alignment: .leading)
        Color.clear
          .frame(width: cutout.width + 24)
        tools
          .padding(.trailing, 18)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    } else {
      HStack {
        title
        Spacer()
        tools
          .padding(.trailing, 18)
      }
    }
  }
}

/// The card under the pointer, for Space. A plain reference, so the pointer going from card to card redraws nothing.
@MainActor
private final class CardUnderPointer {
  private(set) var id: ClipboardItem.ID?

  /// The pointer came over a card or left it; a card that goes from the screen under the pointer counts as left.
  func hovered(_ card: ClipboardItem.ID, _ isOver: Bool) {
    if isOver {
      id = card
    } else if id == card {
      id = nil
    }
  }
}

/// The look of Tasks' search field: a magnifier, "Search", a button that empties it. Esc empties it too; in an empty
/// field Esc goes on to the window, which closes.
struct SearchField: View {
  @Binding var query: String
  var isFocused: FocusState<Bool>.Binding

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11))
        .foregroundStyle(VortexColor.tertiaryText)
      TextField(text: $query) {
        Text("Search", bundle: .module)
      }
      .textFieldStyle(.plain)
      .font(.system(size: 12.5))
      .focused(isFocused)
      .onKeyPress(.escape) {
        guard !query.isEmpty else { return .ignored }
        query = ""
        return .handled
      }
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 11))
            .foregroundStyle(VortexColor.tertiaryText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Clear search", bundle: .module))
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 30)
    .background(Capsule().fill(VortexColor.raised))
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
