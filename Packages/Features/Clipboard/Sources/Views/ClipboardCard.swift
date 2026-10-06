import SwiftUI
import VortexCore
import VortexPlatform

/// One item of the history: a preview, where it was copied and when. Pin and delete appear on hover.
struct ClipboardCard: View {
  let item: ClipboardItem
  let isUnavailable: Bool
  let isRevealed: Bool
  let isJustCopied: Bool
  let now: Date
  let send: @MainActor (ClipboardFeature.Action) -> Void
  @State private var isHovered = false

  private var isImage: Bool {
    if case .image = item.content { true } else { false }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      preview
      Spacer(minLength: 6)
      footer
        .padding(.horizontal, isImage ? 6 : 0)
    }
    .padding(isImage ? EdgeInsets(top: 8, leading: 8, bottom: 12, trailing: 8) : EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
    .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
    .background {
      let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
      shape.fill(VortexColor.card)
      shape.strokeBorder(VortexColor.cardEdge, lineWidth: 0.5)
    }
    .opacity(isUnavailable ? 0.45 : 1)
    .overlay {
      DragSourceArea(
        items: { isUnavailable ? [] : item.dragItems(isRevealed: isRevealed) },
        onClick: { _ in send(.itemTapped(item.id)) },
        onHover: { isHovered = $0 }
      )
    }
    .overlay(alignment: .topTrailing) { buttons }
    .overlay {
      if isJustCopied {
        CopiedBadge()
          .transition(.opacity)
      }
    }
    .contextMenu { menu }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityHint(Text("Copies it again", bundle: .module))
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { send(.itemTapped(item.id)) }
    .accessibilityAction(named: item.isPinned ? Text("Unpin", bundle: .module) : Text("Pin", bundle: .module)) {
      send(.pinTapped(item.id))
    }
    .accessibilityAction(named: Text("Delete", bundle: .module)) { send(.deleteTapped(item.id)) }
  }

  // MARK: - Preview

  @ViewBuilder
  private var preview: some View {
    if item.isConcealed && !isRevealed {
      Text(verbatim: "••••••••")
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .padding(.top, 2)
    } else {
      switch item.content {
      case let .text(text):
        // Only the start: laying out megabytes of text for four lines would stall the window.
        Text(verbatim: String(text.prefix(600)).trimmingCharacters(in: .whitespacesAndNewlines))
          .font(.system(size: 11.5, design: .monospaced))
          .lineSpacing(3)
          .lineLimit(4)
      case let .link(url):
        VStack(alignment: .leading, spacing: 2) {
          Image(systemName: "link")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(VortexColor.tertiaryText)
            .padding(.bottom, 8)
          Text(verbatim: url.host() ?? url.absoluteString)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
          Text(verbatim: Self.pathAndQuery(of: url))
            .font(.system(size: 12))
            .foregroundStyle(VortexColor.secondaryText)
            .lineLimit(1)
        }
      case .image:
        if let url = item.imageURL {
          FileThumbnail(url: url, size: CGSize(width: 200, height: 132)) {
            Image(systemName: "photo")
              .font(.system(size: 18))
              .foregroundStyle(VortexColor.tertiaryText)
          }
          .frame(maxWidth: .infinity, minHeight: 66, maxHeight: 66)
          .background(VortexColor.thumbnail)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
      case let .files(urls):
        HStack(spacing: 10) {
          if let first = urls.first {
            FileIcon(url: first)
              .frame(width: 30, height: 30)
          }
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: urls.first?.lastPathComponent ?? "")
              .font(.system(size: 13, weight: .medium))
              .lineLimit(1)
              .truncationMode(.middle)
            if urls.count > 1 {
              Text("and \(urls.count - 1) more", bundle: .module)
                .font(.system(size: 12))
                .foregroundStyle(VortexColor.secondaryText)
            }
          }
        }
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 5) {
      if let source = item.source {
        AppIcon(bundleID: source.bundleID)
          .frame(width: 13, height: 13)
      }
      Group {
        if isUnavailable {
          Text("Not found", bundle: .module)
        } else if let source = item.source {
          Text(verbatim: source.name) + Text(verbatim: " · ") + Text(age: item.copiedAt, now: now)
        } else {
          Text(age: item.copiedAt, now: now)
        }
      }
      .font(.system(size: 11))
      .foregroundStyle(VortexColor.tertiaryText)
      .lineLimit(1)
      if item.isPinned {
        Spacer(minLength: 4)
        Image(systemName: "pin.fill")
          .font(.system(size: 9))
          .foregroundStyle(VortexColor.tertiaryText)
          .accessibilityHidden(true)
      }
    }
  }

  // MARK: - Buttons

  private var buttons: some View {
    HStack(spacing: 2) {
      if item.isConcealed {
        CardButton(
          symbol: isRevealed ? "eye.slash" : "eye",
          label: isRevealed ? Text("Hide", bundle: .module) : Text("Show", bundle: .module)
        ) {
          send(.revealTapped(item.id))
        }
      }
      if isHovered {
        CardButton(
          symbol: item.isPinned ? "pin.fill" : "pin",
          label: item.isPinned ? Text("Unpin", bundle: .module) : Text("Pin", bundle: .module)
        ) {
          send(.pinTapped(item.id))
        }
      }
      if isHovered {
        CardButton(symbol: "xmark", label: Text("Delete", bundle: .module)) {
          send(.deleteTapped(item.id))
        }
      }
    }
    .padding(6)
  }

  @ViewBuilder
  private var menu: some View {
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
    if case .files = item.content {
      Button {
        send(.showInFinderTapped(item.id))
      } label: {
        Text("Show in Finder", bundle: .module)
      }
      .disabled(isUnavailable)
    }
    Divider()
    Button {
      send(.deleteTapped(item.id))
    } label: {
      Text("Delete", bundle: .module)
    }
  }

  // MARK: - Text

  private var accessibilityLabel: Text {
    let content: Text = if item.isConcealed && !isRevealed {
      Text("Hidden item", bundle: .module)
    } else {
      switch item.content {
      case let .text(text): Text(verbatim: String(text.prefix(200)))
      case let .link(url): Text(verbatim: url.absoluteString)
      case .image: Text("Image", bundle: .module)
      case let .files(urls): Text(verbatim: urls.map(\.lastPathComponent).joined(separator: ", "))
      }
    }
    guard let source = item.source else { return content }
    return content + Text(verbatim: ", ") + Text(verbatim: source.name)
  }

  static func pathAndQuery(of url: URL) -> String {
    var path = url.path()
    if let query = url.query() { path += "?" + query }
    return path.isEmpty || path == "/" ? url.absoluteString : path
  }
}

/// A small round button in the corner of a card.
private struct CardButton: View {
  let symbol: String
  let label: Text
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(VortexColor.secondaryText)
        .frame(width: 24, height: 24)
        .background(Circle().fill(VortexColor.raised))
        .frame(width: 30, height: 30)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(label)
    .accessibilityLabel(label)
  }
}

private struct CopiedBadge: View {
  var body: some View {
    Label {
      Text("Copied", bundle: .module)
    } icon: {
      Image(systemName: "checkmark")
    }
    .font(.system(size: 12, weight: .semibold))
    .padding(.horizontal, 12)
    .frame(height: 28)
    .background(Capsule().fill(VortexColor.accent))
    .foregroundStyle(VortexColor.onAccent)
    .allowsHitTesting(false)
  }
}
