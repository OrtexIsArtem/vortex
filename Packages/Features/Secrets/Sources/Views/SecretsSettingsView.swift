import ComposableArchitecture
import SwiftUI
import VortexCore

/// The Keys section in Settings › Features: connecting Claude Code, and the port it reaches Vortex on.
struct SecretsSettingsView: View {
  let store: StoreOf<SecretsFeature>
  @State private var port = ""
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsRow(title: Text(verbatim: "Claude Code"), caption: status) {
        Button {
          store.send(.copyConnectCommandTapped)
          copied = true
          Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
          }
        } label: {
          Text(copied ? "Copied" : "Copy the connect command", bundle: .module)
        }
        .buttonStyle(.quietCapsule)
        .disabled(store.connectCommand == nil)
      }

      SettingsRow(
        title: Text("Port", bundle: .module),
        caption: Text("Where Claude reaches Vortex on this Mac, at 127.0.0.1. After a change, connect Claude Code again.", bundle: .module)
      ) {
        TextField(text: $port) {
          Text(verbatim: String(SecretsSettings.defaultPort))
        }
        .textFieldStyle(.plain)
        .font(.system(size: 12.5).monospacedDigit())
        .multilineTextAlignment(.trailing)
        .padding(.horizontal, 10)
        .frame(width: 80, height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(VortexColor.raised))
        .onSubmit(applyPort)
      }

      Text("Values stay in the keychain; Claude gets the output with them taken out. The log keeps 30 days.", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
        .padding(.top, 12)
    }
    .onAppear { port = String(store.settings.port) }
  }

  private var status: Text {
    switch store.server {
    case .off: Text("Keys are off.", bundle: .module)
    case .starting: Text("Starting…", bundle: .module)
    case let .listening(port): Text("Waiting for Claude on port \(String(port)). Connect Claude Code once with the command.", bundle: .module)
    case let .failed(message): Text("Not running: \(message)", bundle: .module)
    }
  }

  private func applyPort() {
    guard let value = Int(port.trimmingCharacters(in: .whitespaces)), SecretsSettings.ports.contains(value) else {
      port = String(store.settings.port)
      return
    }
    store.send(.portChanged(value))
  }
}
