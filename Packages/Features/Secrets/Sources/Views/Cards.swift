import ComposableArchitecture
import SwiftUI
import VortexCore

/// Claude asking to use keys: who, which keys, the command and where it runs; «Deny» and «Allow».
struct ApprovalCard: View {
  let approval: Approval
  /// How tall the command may get before it scrolls.
  let commandHeight: CGFloat
  let deny: () -> Void
  let allow: () -> Void
  /// The command is taller than the box: the box fades out at the bottom and says it scrolls.
  @State private var overflows = false

  /// How much of a command a card lays out: laying out more holds up all of Vortex for seconds.
  static let shownLines = 200
  static let shownCharacters = 20_000

  private var lines: [Substring] {
    approval.command.split(separator: "\n", omittingEmptySubsequences: false)
  }

  private var isCut: Bool {
    lines.count > Self.shownLines || approval.command.count > Self.shownCharacters
  }

  private var command: some View {
    let shown = isCut ? String(lines.prefix(Self.shownLines).joined(separator: "\n").prefix(Self.shownCharacters)) + "\n…" : approval.command
    return Text(verbatim: shown)
      .font(.system(size: 11.5, design: .monospaced))
      .foregroundStyle(VortexColor.secondaryText)
      .textSelection(.enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
      .onGeometryChange(for: Bool.self) { $0.size.height > commandHeight + 1 } action: { overflows = $0 }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "key.fill")
          .font(.system(size: 11, weight: .semibold))
        Text("\(approval.call.client) wants to use \(Text(verbatim: approval.names.joined(separator: ", ")).bold())", bundle: .module)
          .font(.system(size: 13))
      }
      // All of it, as the answer is about the command: as tall as it is, up to `commandHeight`, then it scrolls, so the
      // buttons stay where they are.
      ScrollView { command }
        .frame(maxHeight: commandHeight)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .bottom) {
          if overflows {
            LinearGradient(colors: [VortexColor.raised.opacity(0), VortexColor.raised], startPoint: .top, endPoint: .bottom)
              .frame(height: 16)
              .allowsHitTesting(false)
          }
        }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(VortexColor.raised))
      // A tail out of view is part of what is allowed: it is never left unsaid.
      if isCut {
        Text("Only its start is shown: the command is very long (lines: \(lines.count))", bundle: .module)
          .font(.system(size: 11.5))
          .foregroundStyle(VortexColor.primaryText)
      } else if overflows {
        Text("Lines: \(lines.count) — scroll to read it all", bundle: .module)
          .font(.system(size: 11.5))
          .foregroundStyle(VortexColor.tertiaryText)
      }
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

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let failure = store.serverFailure {
        ServerFailureMessage(failure: failure)
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
            CopyButton(Text("Copy", bundle: .module), style: .primaryCapsule, minWidth: 64) {
              store.send(.copyConnectCommandTapped)
            }
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

/// Why Claude can't reach the keys, and what to do: the port the server couldn't listen on and why, or the token the
/// keychain didn't give. The Keys tab's card and the onboarding's Claude Code step show the same text.
struct ServerFailureMessage: View {
  let failure: SecretsFeature.ServerFailure

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Claude can't reach the keys", bundle: .module)
        .font(.system(size: 13, weight: .semibold))
      message
        .font(.system(size: 12))
        .foregroundStyle(VortexColor.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var message: Text {
    switch failure {
    case let .listen(port, failure):
      Text("Vortex could not listen on port \(String(port)): \(failure.reason(port: port)). Pick another port in Settings › Features › Keys.", bundle: .module)
    case .token:
      Text("Vortex could not get its token from the keychain. Restart Vortex and click Always Allow when macOS asks.", bundle: .module)
    }
  }
}

extension MCPFailure {
  /// Why the server couldn't listen, as it reads after a colon: "Not running: Port 47823 is taken".
  func reason(port: Int) -> String {
    switch self {
    // A port reads as a code, «64483», never as a number with a separator for thousands.
    case .portTaken: String(localized: "Port \(String(port)) is taken", bundle: .module)
    case .other: String(localized: "An unexpected error occurred", bundle: .module)
    }
  }
}
