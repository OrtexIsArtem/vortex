import SwiftUI
import VortexCore

/// One key: what it is, its name, how long it lives and when Claude used it; on hover, copying its name, showing the
/// value and the bin.
struct KeyRow: View {
  let key: SecretKey
  /// The value, while the user asked to see it.
  let revealed: String?
  let now: Date
  let send: (SecretsFeature.Action) -> Void
  @State private var isHovered = false
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 12) {
        info
        Spacer(minLength: 8)
        if isHovered {
          tools
            .transition(.opacity)
        }
      }
      // Under the row and as wide as it, so it stays put when the tools come and go.
      if let revealed {
        RevealedValueView(value: revealed, send: send)
          .padding(.top, 8)
          .padding(.leading, 44)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isHovered ? VortexColor.raised.opacity(0.5) : .clear))
    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .onHover { isHovered = $0 }
    .animation(.easeOut(duration: 0.12), value: isHovered)
    .accessibilityElement(children: .combine)
    .accessibilityAction(named: Text("Copy the name", bundle: .module)) { send(.copyNameTapped(key.id)) }
    .accessibilityAction(named: Text("Show the value", bundle: .module)) { send(.revealTapped(key.id)) }
    .accessibilityAction(named: Text("Delete the key", bundle: .module)) { send(.deleteTapped(key.id)) }
  }

  /// The kind's symbol, the name, the details and the note.
  private var info: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: key.kind.symbol)
        .font(.system(size: 13))
        .foregroundStyle(VortexColor.secondaryText)
        .frame(width: 32, height: 32)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(VortexColor.raised))
      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: key.name)
          .font(.system(size: 13, weight: .semibold, design: .monospaced))
          .lineLimit(1)
        details
          .font(.system(size: 11.5))
          .foregroundStyle(VortexColor.tertiaryText)
          .lineLimit(1)
        if !key.note.isEmpty {
          Text(verbatim: key.note)
            .font(.system(size: 12))
            .foregroundStyle(VortexColor.secondaryText)
            .lineLimit(2)
        }
      }
    }
  }

  /// «PostgreSQL · until 18:40 · used 14:21».
  private var details: Text {
    var parts = [key.kind.title, expiry]
    if let used = key.lastUsedAt {
      parts.append(Text("used \(Text(age: used, now: now))", bundle: .module))
    }
    return parts.dropFirst().reduce(parts[0]) { $0 + Text(verbatim: " · ") + $1 }
  }

  private var expiry: Text {
    guard let expiresAt = key.expiresAt else { return Text("for good", bundle: .module) }
    let time = expiresAt.formatted(date: .omitted, time: .shortened)
    if Calendar.current.isDate(expiresAt, inSameDayAs: now) {
      return Text("until \(time)", bundle: .module)
    }
    return Text("until \(expiresAt.formatted(.dateTime.day().month(.abbreviated))), \(time)", bundle: .module)
  }

  private var tools: some View {
    HStack(spacing: 4) {
      Button {
        send(.copyNameTapped(key.id))
        copied = true
        Task {
          try? await Task.sleep(for: .seconds(1.5))
          copied = false
        }
      } label: {
        Text(copied ? "Copied" : "Copy the name", bundle: .module)
          .frame(minWidth: 96)
      }
      .buttonStyle(QuietCapsuleButtonStyle(height: 28, fontSize: 11.5))
      .help(Text("Copies «\(key.name) (Vortex)»: say it to Claude, and it takes the key from Vortex", bundle: .module))
      ToolButton(symbol: revealed == nil ? "eye" : "eye.slash", label: Text("Show the value", bundle: .module)) {
        send(.revealTapped(key.id))
      }
      ToolButton(symbol: "trash", label: Text("Delete the key", bundle: .module)) {
        send(.deleteTapped(key.id))
      }
    }
  }
}

/// A small round button with a symbol.
private struct ToolButton: View {
  let symbol: String
  let label: Text
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 12))
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(VortexColor.secondaryText)
    .help(label)
    .accessibilityLabel(label)
  }
}

/// The value, with a button that copies it without leaving it in clipboard histories.
private struct RevealedValueView: View {
  let value: String
  let send: (SecretsFeature.Action) -> Void

  var body: some View {
    HStack(spacing: 8) {
      Text(verbatim: value)
        .font(.system(size: 11.5, design: .monospaced))
        .textSelection(.enabled)
        .lineLimit(3)
        .truncationMode(.middle)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VortexColor.raised))
      Button {
        send(.copyValueTapped)
      } label: {
        Text("Copy", bundle: .module)
      }
      .buttonStyle(QuietCapsuleButtonStyle(height: 26, fontSize: 11.5))
    }
  }
}
