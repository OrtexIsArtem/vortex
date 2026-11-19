import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The clipboard on Home: the history as one-line rows. A click copies again, a row drags out, its eye shows it in
/// Quick Look, a drop copies.
struct ClipboardHomeWidget: View {
  let store: StoreOf<ClipboardFeature>
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
            // At most 10 pinned, then the newest: 20 rows (`homeItems`); the tab has the rest.
            ForEach(Array(store.homeItems.enumerated()), id: \.element.id) { index, item in
              if index > 0 {
                Hairline().padding(.leading, ClipboardRow.textInset)
              }
              ClipboardRow(
                item: item,
                isUnavailable: store.unavailable.contains(item.id),
                isJustCopied: store.justCopied == item.id,
                wholeText: store.wholeText?.id == item.id ? store.wholeText?.text : nil
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
    .modifier(ClipboardVisibilityTracking(store: store))
  }
}

/// One item of the history in one line: a tiny picture of an image, an icon for any other kind, and the start of it.
/// Secrets stay dots. Under the pointer, Quick Look's eye shows at its end.
private struct ClipboardRow: View {
  let item: ClipboardItem
  let isUnavailable: Bool
  let isJustCopied: Bool
  /// The whole text of a long item, once read: without it a long text doesn't drag.
  let wholeText: String?
  let send: @MainActor (ClipboardFeature.Action) -> Void
  @State private var isHovered = false

  /// The column of the picture or the icon, as wide as a picture in every row, so all the text starts at one place.
  static let leadingWidth: CGFloat = 22
  static let spacing: CGFloat = 10
  /// Where the text starts; the hairlines between rows start there too.
  static let textInset = leadingWidth + spacing
  static let height: CGFloat = 34
  /// The eye's target: 44 pt wide and as tall as the row, as a taller one would reach into the rows around it.
  static let eyeTarget = CGSize(width: 44, height: height)
  /// What the text leaves the eye at the row's end.
  static let eyeRoom: CGFloat = 28

  private var opensInQuickLook: Bool {
    item.opensInQuickLook(isUnavailable: isUnavailable)
  }

  private var showsEye: Bool {
    isHovered && opensInQuickLook
  }

  var body: some View {
    HStack(spacing: Self.spacing) {
      leading
        .frame(width: Self.leadingWidth)
      preview
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 0)
    }
    .padding(.trailing, showsEye ? Self.eyeRoom : 0)
    .frame(height: Self.height)
    .opacity(isUnavailable ? 0.45 : 1)
    .overlay {
      DragSourceArea(
        // Home has no Show for a secret, so a secret never drags from here.
        items: { isUnavailable ? [] : item.dragItems(isRevealed: false, wholeText: wholeText) },
        onClick: { _ in send(.itemTapped(item.id)) },
        onHover: { isHovered in
          self.isHovered = isHovered
          // A long text drags out whole: its whole text is read while the pointer is over it.
          if isHovered, item.isTruncated { send(.itemHovered(item.id)) }
        }
      )
    }
    .overlay(alignment: .trailing) {
      if showsEye { eye }
    }
    .contextMenu {
      Button {
        send(.itemTapped(item.id))
      } label: {
        Text("Copy", bundle: .module)
      }
      .disabled(isUnavailable)
      if !item.isConcealed {
        Button {
          send(.quickLookTapped(item.id))
        } label: {
          Text("Quick Look", bundle: .module)
        }
        .disabled(isUnavailable)
      }
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
    .accessibilityActions {
      if opensInQuickLook {
        Button {
          send(.quickLookTapped(item.id))
        } label: {
          Text("Quick Look", bundle: .module)
        }
      }
    }
  }

  /// Quick Look's eye, quiet as the row's icons, at the row's end.
  private var eye: some View {
    Button {
      send(.quickLookTapped(item.id))
    } label: {
      Image(systemName: "eye")
        .font(.system(size: 12))
        .foregroundStyle(VortexColor.secondaryText)
        .frame(width: Self.eyeTarget.width, height: Self.eyeTarget.height, alignment: .trailing)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(Text("Quick Look", bundle: .module))
    .accessibilityLabel(Text("Quick Look", bundle: .module))
  }

  /// The picture of an image; for anything else, or until the picture is made, the icon of its kind. After a click the
  /// check stands in for the icon, or over the picture.
  @ViewBuilder private var leading: some View {
    if !item.isConcealed, let url = item.imageURL {
      // Quick Look fits the picture inside the size asked and the tile crops it to a square: twice the tile keeps a
      // picture up to twice as wide as tall sharp.
      FileThumbnail(url: url, size: CGSize(width: Self.leadingWidth * 2, height: Self.leadingWidth * 2)) {
        icon("photo")
      }
      .frame(width: Self.leadingWidth, height: Self.leadingWidth)
      .background(VortexColor.thumbnail)
      .overlay {
        if isJustCopied {
          ZStack {
            Color.black.opacity(0.5)
            Image(systemName: "checkmark")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.white)
          }
          .transition(.opacity)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    } else {
      icon(isJustCopied ? "checkmark" : symbol)
    }
  }

  private func icon(_ name: String) -> some View {
    Image(systemName: name)
      .font(.system(size: 12))
      .foregroundStyle(VortexColor.tertiaryText)
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
      return Text(verbatim: LinkAddress.readable((url.host() ?? "") + url.path())).font(.system(size: 12))
    case .image:
      return Text("Image", bundle: .module).font(.system(size: 12))
    case let .files(urls):
      let more = urls.count > 1 ? " +\(urls.count - 1)" : ""
      return Text(verbatim: (urls.first.map(FileName.shown) ?? "") + more).font(.system(size: 12))
    }
  }
}
