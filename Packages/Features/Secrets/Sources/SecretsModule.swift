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

  /// The onboarding's Claude Code step: done once Connect worked or Claude Code connected.
  public static func makeOnboardingStep() -> OnboardingStep? {
    OnboardingStep(id: id, title: LocalizedStringResource(stringLiteral: "Claude Code"), view: ClaudeCodeStepView(store: store))
  }

  public static func setEnabled(_ isEnabled: Bool) {
    #if DEBUG
      // A QA run takes commands only on its own channel (VortexPlatform's `QA`).
      if !isListening {
        isListening = true
        if QA.isActive { registerQACommands() } else { listenForDebugCommands() }
      }
    #endif
    store.send(isEnabled ? .start : .stop)
  }

  #if DEBUG
    /// The onboarding shows the Claude Code step now: its view appeared and hasn't gone.
    static var isStepShowing = false

    /// QA mode: `keys press=connect|connectAgain|copyCommand|getClaudeCode` presses the Claude Code step's buttons,
    /// refused while the step doesn't show them; `press=turnOn|restart` the Notifications row in the settings;
    /// `press=allow|deny` answers the first request waiting; `add=<name> value=<value> [note=<text>]` saves a key as the
    /// form does; `claude=<command> [folder=<path>]` is Claude Code's `run` call as the MCP server hands it over, without
    /// the network or the token. The `keys` state section shows the step, never the token or the command.
    private static func registerQACommands() {
      QA.registerState(section: "keys") { StepState(store.state) }
      QA.register(command: "keys") { arguments in
        let state = store.state
        if let name = arguments["add"] {
          guard let value = arguments["value"], !value.isEmpty else { throw QAError("keys add= needs value=") }
          store.send(.addTapped)
          store.send(.draftChanged(KeyDraft(name: name, value: value, note: arguments["note"] ?? "")))
          store.send(.saveTapped)
          return
        }
        if let command = arguments["claude"] {
          let session = MCPSession(id: "qa-claude-code", client: "Claude Code")
          if state.sessions[session.id] == nil { store.send(.server(.sessionStarted(session))) }
          var call: [String: JSONValue] = ["command": .string(command)]
          if let folder = arguments["folder"] { call["cwd"] = .string(folder) }
          store.send(.server(.call(MCPCall(
            id: UUID(), session: session.id, client: session.client, tool: .run, arguments: .object(call)
          ))))
          return
        }
        let stepPresses: Set<String> = ["connect", "connectAgain", "copyCommand", "getClaudeCode"]
        if let press = arguments["press"], stepPresses.contains(press), !isStepShowing {
          throw QAError("the Claude Code step's buttons are on its onboarding page, which isn't showing")
        }
        switch arguments["press"] {
        case "allow", "deny":
          guard let id = state.approvals.first?.id else { throw QAError("no request is waiting for Allow") }
          store.send(arguments["press"] == "allow" ? .approveTapped(id) : .denyTapped(id))
        case "connect", "connectAgain":
          let again = arguments["press"] == "connectAgain"
          let showsConnected = state.showsConnectAgain
          guard state.canConnect, again == showsConnected else {
            throw QAError("\(again ? "Connect again" : "Connect") isn't there or is disabled now")
          }
          store.send(.connectTapped)
        case "copyCommand":
          switch state.connect {
          case .notInstalled, .failed: store.send(.copyConnectCommandTapped)
          case .idle, .running, .added: throw QAError("Copy command shows only after Connect failed")
          }
        case "getClaudeCode":
          guard state.connect == .notInstalled else { throw QAError("the link shows only when Claude Code isn't installed") }
          store.send(.getClaudeCodeTapped)
        default:
          let pressed = try QAPermissions.pressRow(
            arguments,
            needs: permissionNeeds,
            statuses: state.permissionStatuses,
            turnOn: { store.send(.turnOnTapped($0)) },
            restart: { store.send(.restartTapped) }
          )
          guard pressed else {
            throw QAError(
              "keys takes add=, or press=allow, deny, connect, connectAgain, copyCommand, getClaudeCode, turnOn or restart"
            )
          }
        }
      }
    }

    /// The Claude Code step as QA's state shows it.
    struct StepState: Encodable {
      var server: String
      var connect: String
      var canConnect: Bool
      var connected: Bool
      var hasConnected: Bool
      var addedToClaudeCode: Bool
      var stepDone: Bool
      /// The port the step names when the server is down (the Keys card's message), or nil while it shows Connect.
      var serverFailurePort: Int?

      init(_ state: SecretsFeature.State) {
        server = switch state.server {
        case .off: "off"
        case .starting: "starting"
        case .listening: "listening"
        case .failed: "failed"
        }
        connect = switch state.connect {
        case .idle: "idle"
        case .running: "running"
        case .added: "added"
        case .notInstalled: "notInstalled"
        case let .failed(exitCode): "failed \(exitCode)"
        }
        canConnect = state.canConnect
        connected = state.isConnectedNow
        hasConnected = state.settings.hasConnected
        addedToClaudeCode = state.settings.addedToClaudeCode
        @Shared(.onboardingStepsDone) var done
        stepDone = done.contains(SecretsFeature.id)
        if case let .serverFailure(failure) = state.claudeStepBody { serverFailurePort = failure.port }
      }
    }
  #endif

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
