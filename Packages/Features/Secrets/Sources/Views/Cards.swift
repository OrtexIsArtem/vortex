import ComposableArchitecture
import SwiftUI
import VortexCore

/// Claude asking to use keys: who, which keys, the command and where it runs; «Відхилити» and «Дозволити».
struct ApprovalCard: View {
  let approval: Approval
  let deny: () -> Void
  let allow: () -> Void

  private var command: some View {
    Text(verbatim: approval.command)
      .font(.system(size: 11.5, design: .monospaced))
      .foregroundStyle(VortexColor.secondaryText)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "key.fill")
          .font(.system(size: 11, weight: .semibold))
        Text("\(approval.call.client) wants to use \(Text(verbatim: approval.names.joined(separator: ", ")).bold())", bundle: .module)
          .font(.system(size: 13))
      }
      // All of it, as the answer is about the command: past a few lines it scrolls, so the buttons stay where they are.
      ViewThatFits(in: .vertical) {
        command
        ScrollView { command }
      }
      .frame(maxHeight: 150)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(VortexColor.raised))
      HStack(spacing: 8) {
        Group {
          if let folder = approval.folder {
            Text(verbatim: (folder as NSString).abbreviatingWithTildeInPath)
          } else {
            Text("Until this session ends, it won't ask again.", bundle: .module)
          }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
        .lineLimit(1)
        .truncationMode(.head)
        Spacer(minLength: 8)
        Button(action: deny) {
          Text("Deny", bundle: .module)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(VortexColor.secondaryText)
        Button(action: allow) {
          Text("Allow", bundle: .module)
        }
        .buttonStyle(.primaryCapsule)
      }
    }
    .padding(14)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(VortexColor.card))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(VortexColor.accent.opacity(0.35))
        .allowsHitTesting(false)
    )
  }
}

/// How to connect Claude Code, once for every project; or why the server is not running.
struct ConnectCard: View {
  let store: StoreOf<SecretsFeature>
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if case let .failed(message) = store.server {
        Text("Claude can't reach the keys", bundle: .module)
          .font(.system(size: 13, weight: .semibold))
        Text("Vortex could not listen on port \(String(store.settings.port)): \(message). Pick another port in Settings › Features › Keys.", bundle: .module)
          .font(.system(size: 12))
          .foregroundStyle(VortexColor.secondaryText)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("Connect Claude Code once", bundle: .module)
          .font(.system(size: 13, weight: .semibold))
        Text("Run this in Terminal, and Claude can use the keys in every project.", bundle: .module)
          .font(.system(size: 12))
          .foregroundStyle(VortexColor.secondaryText)
        if let command = store.connectCommand {
          HStack(spacing: 8) {
            Text(verbatim: Self.shown(command))
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(VortexColor.secondaryText)
              .lineLimit(2)
              .truncationMode(.tail)
              .padding(.horizontal, 10)
              .padding(.vertical, 7)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(VortexColor.raised))
            Button {
              store.send(.copyConnectCommandTapped)
              copied = true
              Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
              }
            } label: {
              Text(copied ? "Copied" : "Copy", bundle: .module)
                .frame(minWidth: 64)
            }
            .buttonStyle(.primaryCapsule)
          }
        }
      }
    }
    .padding(14)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(VortexColor.card))
    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(VortexColor.line).allowsHitTesting(false))
  }

  /// The command with its token hidden: it is copied whole, but not shown.
  static func shown(_ command: String) -> String {
    guard let range = command.range(of: "Bearer ") else { return command }
    return command[..<range.upperBound] + "••••••\""
  }
}
