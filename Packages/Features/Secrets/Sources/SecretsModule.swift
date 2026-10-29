import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// Entry point the app shell reads; registered in Features/Registry.
@MainActor
public enum SecretsModule: FeatureModule {
  public static let id: FeatureID = SecretsFeature.id
  public static let title = LocalizedStringResource("Keys", bundle: .atURL(Bundle.module.bundleURL))
  public static let symbol = "key.horizontal"
  public static let permissionNeeds = [
    PermissionNeed(
      .notifications,
      reason: LocalizedStringResource("Shows Claude's key requests when the window is closed.", bundle: .atURL(Bundle.module.bundleURL))
    ),
  ]

  /// One store for the life of the app: Claude reaches the keys while the window is closed.
  static let store = Store(initialState: SecretsFeature.State()) {
    SecretsFeature()
  }

  private static var isListening = false

  public static func makeTab() -> AnyView {
    AnyView(SecretsView(store: store))
  }

  public static func makeSettings() -> AnyView? {
    AnyView(SecretsSettingsView(store: store))
  }

  public static func setEnabled(_ isEnabled: Bool) {
    #if DEBUG
      // A QA run takes commands only on its own channel (VortexPlatform's `QA`).
      if !isListening, !QA.isActive {
        isListening = true
        listenForDebugCommands()
      }
    #endif
    store.send(isEnabled ? .start : .stop)
  }

  #if DEBUG
    /// Lets scripts drive keys in a debug build, through distributed notifications:
    /// `io.github.ortexisartem.vortex.debug.secretsAdd` saves a key (userInfo `name`, `value`, optional `note`),
    /// `…secretsDelete` deletes one (userInfo `name`), `…secretsCopyConnect` copies the connect command,
    /// `…secretsDeny` refuses the first waiting request, `…secretsState` writes what the feature holds to the file at
    /// userInfo `path`, as JSON, never a value. Nothing approves a request: only a person does, in every build.
    private static func listenForDebugCommands() {
      let center = DistributedNotificationCenter.default()
      func on(_ name: String, _ handle: @escaping @MainActor ([String: String]) -> Void) {
        center.addObserver(forName: Notification.Name("io.github.ortexisartem.vortex.debug.\(name)"), object: nil, queue: .main) { note in
          let info = note.userInfo as? [String: String] ?? [:]
          MainActor.assumeIsolated { handle(info) }
        }
      }
      on("secretsAdd") { info in
        store.send(.addTapped)
        store.send(.draftChanged(KeyDraft(name: info["name"] ?? "", value: info["value"] ?? "", note: info["note"] ?? "")))
        store.send(.saveTapped)
      }
      on("secretsDelete") { info in
        if let key = store.keys.first(where: { $0.name == info["name"] }) { store.send(.deleteTapped(key.id)) }
      }
      on("secretsCopyConnect") { _ in store.send(.copyConnectCommandTapped) }
      on("secretsDeny") { _ in
        if let id = store.approvals.first?.id { store.send(.denyTapped(id)) }
      }
      on("secretsState") { info in
        guard let path = info["path"] else { return }
        let server: String = switch store.server {
        case .off: "off"
        case .starting: "starting"
        case let .listening(port): "listening \(port)"
        case let .failed(message): "failed: \(message)"
        }
        let state: [String: Any] = [
          "server": server,
          "sessions": store.sessions.count,
          "approvals": store.approvals.map { ["names": $0.names, "command": $0.command] },
          "keys": store.keys.map { ["name": $0.name, "kind": $0.kind.rawValue, "expires": $0.expiresAt?.description ?? ""] },
          "hasToken": store.token != nil,
        ]
        try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
          .write(to: URL(fileURLWithPath: path))
      }
    }
  #endif
}
