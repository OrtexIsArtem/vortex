import SwiftUI
import VortexCore
import VortexPlatform

/// One thing on the shelf: a preview, its name, its size and age.
struct ShelfTile: View {
  let item: ShelfItem
  let info: FileInfo?
  let isSelected: Bool
  let isFresh: Bool
  let isUnavailable: Bool
  let now: Date
  let dragItems: @MainActor () -> [DragItem]
  let send: @MainActor (ShelfFeature.Action) -> Void
  @State private var isHovered = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      preview
        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 100)
        .background(VortexColor.thumbnail)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
          // Around the preview, not over it, so it shows on white images too.
          if isSelected {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
              .strokeBorder(VortexColor.accent, lineWidth: 2)
              .padding(-3)
          }
        }
        .overlay(alignment: .topTrailing) {
          if isFresh && !isHovered {
            Circle()
              .fill(VortexColor.primaryText)
              .frame(width: 6, height: 6)
              .padding(10)
              .accessibilityHidden(true)
          }
        }
      Text(verbatim: title)
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.top, 8)
      details
        .font(.system(size: 11))
        .foregroundStyle(VortexColor.tertiaryText)
        .lineLimit(1)
        .padding(.top, 2)
    }
    .opacity(isUnavailable ? 0.45 : 1)
    .overlay {
      DragSourceArea(
        items: dragItems,
        onClick: { send(.itemClicked(item.id, $0)) },
        onHover: { isHovered = $0 }
      )
    }
    .overlay(alignment: .topTrailing) {
      if isHovered {
        Button {
          send(.removeTapped(item.id))
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(VortexColor.secondaryText)
            .frame(width: 24, height: 24)
            .background(Circle().fill(VortexColor.raised))
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("Remove from the shelf", bundle: .module))
        .accessibilityLabel(Text("Remove from the shelf", bundle: .module))
      }
    }
    .contextMenu { menu }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: title))
    .accessibilityValue(details)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityAction { send(.itemClicked(item.id, DragSourceClick(count: 1, modifiers: []))) }
    .accessibilityAction(named: Text("Quick Look", bundle: .module)) { send(.quickLookTapped(item.id)) }
    .accessibilityAction(named: Text("Remove from the shelf", bundle: .module)) { send(.removeTapped(item.id)) }
  }

  // MARK: - Preview

  @ViewBuilder
  private var preview: some View {
    switch item.content {
    case .file, .copy:
      if let url = item.fileURL {
        if info?.isDirectory == true {
          FileIcon(url: url)
            .frame(width: 56, height: 56)
        } else {
          FileThumbnail(url: url, size: CGSize(width: 150, height: 100)) {
            if url.pathExtension.isEmpty {
              FileIcon(url: url)
                .frame(width: 48, height: 48)
            } else {
              Text(verbatim: "." + url.pathExtension.lowercased())
                .font(.system(size: 18, weight: .light, design: .monospaced))
                .foregroundStyle(VortexColor.secondaryText)
                .lineLimit(1)
                .padding(.horizontal, 8)
            }
          }
        }
      }
    case let .text(text):
      Text(verbatim: String(text.prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines))
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(VortexColor.secondaryText)
        .lineLimit(5)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    case let .link(url):
      VStack(spacing: 8) {
        Image(systemName: "link")
          .font(.system(size: 16))
        Text(verbatim: url.host() ?? url.absoluteString)
          .font(.system(size: 11, weight: .medium))
          .lineLimit(1)
          .padding(.horizontal, 10)
      }
      .foregroundStyle(VortexColor.secondaryText)
    }
  }

  private var title: String {
    switch item.content {
    case .file, .copy:
      item.fileURL?.lastPathComponent ?? ""
    case let .text(text):
      text.prefix(200).split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    case let .link(url):
      url.host() ?? url.absoluteString
    }
  }

  /// "48.2 MB · now", "Folder · 2 h", "Not found".
  private var details: Text {
    if isUnavailable {
      return Text("Not found", bundle: .module)
    }
    var parts: [Text] = []
    if let info {
      if info.isDirectory {
        parts.append(Text("Folder", bundle: .module))
      } else if let size = info.size {
        parts.append(Text(size, format: .byteCount(style: .file)))
      }
    }
    parts.append(Text(age: item.addedAt, now: now))
    if item.isPinned {
      parts.append(Text(Image(systemName: "pin.fill")))
    }
    return parts.dropFirst().reduce(parts[0]) { $0 + Text(verbatim: " · ") + $1 }
  }

  @ViewBuilder
  private var menu: some View {
    if item.fileURL != nil {
      Button {
        send(.quickLookTapped(item.id))
      } label: {
        Text("Quick Look", bundle: .module)
      }
      .disabled(isUnavailable)
      Button {
        send(.showInFinderTapped(item.id))
      } label: {
        Text("Show in Finder", bundle: .module)
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
      // Like Finder: the menu of a selected item acts on the whole selection.
      send(isSelected ? .removeSelectedPressed : .removeTapped(item.id))
    } label: {
      Text("Remove from the shelf", bundle: .module)
    }
  }
}
