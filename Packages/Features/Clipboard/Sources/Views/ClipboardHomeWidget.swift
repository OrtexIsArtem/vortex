import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The clipboard on Home: the history as one-line rows. A click copies again, a row drags out, a drop copies.
struct ClipboardHomeWidget: View {
  let store: StoreOf<ClipboardFeature>
  @Environment(\.isWindowOpen) private var isWindowOpen
  @State private var isTargeted = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Clipboard", bundle: .module)
        .font(.system(size: 12))
        .foregroundStyle(VortexColor.secondaryText)
        .frame(height: 18)
      if store.items.isEmpty {
        Text("Nothing copied yet", bundle: .module)
          .font(.system(size: 11.5))
          .foregroundStyle(VortexColor.tertiaryText)
          .padding(.top, 4)
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
              if index > 0 {
                Hairline().padding(.leading, 24)
              }
              ClipboardRow(
                item: item,
                isUnavailable: store.unavailable.contains(item.id),
                isJustCopied: store.justCopied == item.id
              ) { store.send($0, animation: .snappy(duration: 0.25)) }
            }
          }
        }
        .scrollIndicators(.never)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .overlay {
      if isTargeted {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(VortexColor.accent, lineWidth: 1.5)
          .padding(-6)
          .overlay {
            Text("Release to copy", bundle: .module)
              .font(.system(size: 12, weight: .medium))
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(Capsule().fill(VortexColor.raised))
          }
          .allowsHitTesting(false)
      }
    }
    .animation(.easeOut(duration: 0.15), value: isTargeted)
    .dropTarget(isTargeted: $isTargeted) { items in
      store.send(.dropped(items))
    }
    .task(id: isWindowOpen) {
      if isWindowOpen { store.send(.tabShown) }
    }
  }
}

/// One item of the history in one line: an icon for its kind and the start of it. Secrets stay dots.
private struct ClipboardRow: View {
  let item: ClipboardItem
  let isUnavailable: Bool
  let isJustCopied: Bool
  let send: @MainActor (ClipboardFeature.Action) -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: isJustCopied ? "checkmark" : symbol)
        .font(.system(size: 12))
        .foregroundStyle(VortexColor.tertiaryText)
        .frame(width: 14)
      preview
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 0)
    }
    .frame(height: 34)
    .opacity(isUnavailable ? 0.45 : 1)
    .overlay {
      DragSourceArea(
        // Home has no eye to show a secret, so a secret never drags from here.
        items: { isUnavailable ? [] : item.dragItems(isRevealed: false) },
        onClick: { _ in send(.itemTapped(item.id)) }
      )
    }
    .contextMenu {
      Button {
        send(.itemTapped(item.id))
      } label: {
        Text("Copy", bundle: .module)
      }
      .disabled(isUnavailable)
      Button {
        send(.pinTapped(item.id))
      } label: {
        item.isPinned ? Text("Unpin", bundle: .module) : Text("Pin", bundle: .module)
      }
      Divider()
      Button {
        send(.deleteTapped(item.id))
      } label: {
        Text("Delete", bundle: .module)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(item.isConcealed ? Text("Hidden item", bundle: .module) : preview)
    .accessibilityHint(Text("Copies it again", bundle: .module))
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { send(.itemTapped(item.id)) }
  }

  private var symbol: String {
    if item.isConcealed { return "lock" }
    switch item.content {
    case .text: return "text.alignleft"
    case .link: return "link"
    case .image: return "photo"
    case .files: return "doc"
    }
  }

  private var preview: Text {
    if item.isConcealed {
      return Text(verbatim: "••••••••").font(.system(size: 12, design: .monospaced))
    }
    switch item.content {
    case let .text(text):
      let line = text.prefix(300).split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
      return Text(verbatim: line).font(.system(size: 11.5, design: .monospaced))
    case let .link(url):
      return Text(verbatim: (url.host() ?? "") + url.path()).font(.system(size: 12))
    case .image:
      return Text("Image", bundle: .module).font(.system(size: 12))
    case let .files(urls):
      let more = urls.count > 1 ? " +\(urls.count - 1)" : ""
      return Text(verbatim: (urls.first?.lastPathComponent ?? "") + more).font(.system(size: 12))
    }
  }
}
