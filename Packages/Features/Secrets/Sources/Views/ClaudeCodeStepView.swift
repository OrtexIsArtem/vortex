import ComposableArchitecture
import SwiftUI
import VortexCore

/// The onboarding's Claude Code step (S27, S78), hosted by the shell: "Connect" adds Vortex to Claude Code with the
/// same command as the tab's card, run in the user's login shell. The token never shows: the command reads it from the
/// environment, and only a fixed line with the exit code is shown on a failure.
struct ClaudeCodeStepView: View {
  let store: StoreOf<SecretsFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Let Claude run commands with your saved keys without ever seeing their values. Skip this if you don't use Claude Code.", bundle: .module)
        .foregroundStyle(VortexColor.secondaryText)
        .fixedSize(horizontal: false, vertical: true)

      if case let .failed(message) = store.server {
        // The server isn't running: nothing to connect to, and the onboarding offers Skip.
        Text("Not running: \(message)", bundle: .module)
          .foregroundStyle(VortexColor.secondaryText)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          if store.isConnectedNow || store.settings.hasConnected {
            Text("Connected ✓", bundle: .module)
          }
          controls
          result
        }
      }

      Spacer(minLength: 0)
      Text("You can do this later in the Keys tab.", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    #if DEBUG
      // QA presses the step's buttons only while the onboarding shows it.
      .onAppear { SecretsModule.isStepShowing = true }
      .onDisappear { SecretsModule.isStepShowing = false }
    #endif
  }

  /// "Connect", the page's main button, or once connected or added a quiet "Connect again"; a spinner while it runs.
  private var controls: some View {
    HStack(spacing: 10) {
      if store.showsConnectAgain {
        Button {
          store.send(.connectTapped)
        } label: {
          Text("Connect again", bundle: .module)
        }
        .buttonStyle(.quietCapsule)
        .disabled(!store.canConnect)
      } else {
        Button {
          store.send(.connectTapped)
        } label: {
          Text("Connect", bundle: .module)
        }
        .buttonStyle(.primaryCapsule)
        .disabled(!store.canConnect)
      }
      if store.connect == .running {
        ProgressView().controlSize(.small)
      }
    }
  }

  /// What the last run gave, under either button; after a relaunch, an earlier success (S27, S78).
  @ViewBuilder
  private var result: some View {
    switch store.connect {
    case .running:
      EmptyView()
    case .idle:
      if store.settings.addedToClaudeCode {
        added
      }
    case .added:
      added
    case .notInstalled:
      Text("Claude Code isn't installed", bundle: .module)
      Button {
        store.send(.getClaudeCodeTapped)
      } label: {
        Text(verbatim: "claude.com/claude-code")
      }
      .buttonStyle(.link)
      fallback
    case let .failed(exitCode):
      Text("Couldn't add Vortex to Claude Code (exit code \(Int(exitCode))).", bundle: .module)
      fallback
    }
  }

  private var added: some View {
    Text("Added to Claude Code ✓ — start a new Claude Code session to use your keys.", bundle: .module)
  }

  /// The command to run by hand: copied concealed, as from the tab's card.
  private var fallback: some View {
    HStack(spacing: 10) {
      CopyButton(Text("Copy command", bundle: .module), style: .quietCapsule) {
        store.send(.copyConnectCommandTapped)
      }
      .disabled(store.connectCommand == nil)
      Text("Run it in Terminal", bundle: .module)
        .foregroundStyle(VortexColor.tertiaryText)
    }
  }
}

extension SecretsFeature.State {
  /// "Connect" works only while the server listens (S78), and once at a time.
  var canConnect: Bool {
    guard case .listening = server, token != nil else { return false }
    return connect != .running
  }

  /// A Claude Code session is live now.
  var isConnectedNow: Bool { !sessions.isEmpty }

  /// The step's button reads "Connect again", quiet: a client connected, or Connect worked, also before a relaunch.
  var showsConnectAgain: Bool {
    isConnectedNow || settings.hasConnected || settings.addedToClaudeCode
  }
}
