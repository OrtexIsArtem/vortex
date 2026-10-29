#if DEBUG
  import Foundation
  import VortexCore

  /// macOS's permissions in a QA run: one `SimulatedPermissions`, kept in DataFolder/.qa/permissions.json after every
  /// change, so a relaunch keeps what System Settings holds. Each launch starts from the saved state and calls
  /// `relaunch()`: the new process sees what System Settings holds now. The `perm` command (the shell's) changes it.
  public enum QAPermissions {
    /// The run's simulated macOS.
    public static let simulated: SimulatedPermissions = load()

    static var file: URL { QAPaths.controlFolder.appending(path: "permissions.json") }

    /// The saved state, seen as after a relaunch; a fresh run starts as a fresh Mac: nothing asked, nothing listed.
    static func load() -> SimulatedPermissions {
      guard QA.isActive, let data = try? Data(contentsOf: file),
            let state = try? JSONDecoder().decode(SimulatedPermissions.State.self, from: data)
      else { return SimulatedPermissions() }
      let simulated = SimulatedPermissions(state)
      simulated.relaunch()
      return simulated
    }

    /// Writes the state into the run's folder; outside QA mode, as in tests, nothing is written.
    public static func save() {
      guard QA.isActive else { return }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try? encoder.encode(simulated.state).write(to: file, options: .atomic)
    }

    /// The client of a QA run: the simulation, saved after whatever the app asks of it. As the live client reads again
    /// whenever an app becomes active, `app activate=` reads again too.
    static var client: PermissionsClient {
      Task {
        for await _ in QASystem.shared.activations() {
          simulated.refresh()
        }
      }
      var client = PermissionsClient.simulated(simulated)
      client.request = { permission in
        simulated.request(permission)
        save()
        QALog.record("permissions", "request", ["permission": permission.rawValue])
      }
      client.openSettings = { permission in
        simulated.openSettings(permission)
        save()
        QALog.record("permissions", "openSettings", ["permission": permission.rawValue])
      }
      client.setFrequentChecks = { isOn in
        simulated.setFrequentChecks(isOn)
        save()
      }
      return client
    }

    /// A capture sees the screen: Screen Recording was on when the run started, or is on now with a live grant.
    static var screenCaptureWorks: Bool {
      let state = simulated.state
      return state.settingsAtLaunch[.screenRecording] == .granted
        || (state.liveScreenRecording && state.settings[.screenRecording] == .granted)
    }

    // MARK: - The perm command

    /// `perm set=<p>:<notAsked|denied|granted>[,…]`, `answer=<p>:<allow|deny|ignore>[,…]`, `toggle=<p>:<on|off>[,…]`,
    /// `liveScreenRecording=<bool>`, `pasteboardAsks=<bool>`, `refresh`; several at once apply in that order. Checks
    /// every argument before changing anything. `quitReopen` and `required=` are the shell's.
    public static func apply(_ arguments: [String: String], to simulated: SimulatedPermissions = simulated) throws {
      var changes: [@Sendable () -> Void] = []
      func pairs(_ key: String) throws -> [(Permission, String)] {
        guard let text = arguments[key] else { return [] }
        return try text.split(separator: ",").map { pair in
          let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
          guard parts.count == 2, let permission = Permission(rawValue: parts[0]) else {
            throw QAError("\(key)= takes <permission>:<value>, permission one of \(names), not \"\(pair)\"")
          }
          return (permission, parts[1])
        }
      }
      func flag(_ key: String) throws -> Bool? {
        guard let text = arguments[key] else { return nil }
        guard let value = Bool(text) else { throw QAError("\(key)= takes true or false, not \"\(text)\"") }
        return value
      }
      for (permission, value) in try pairs("set") {
        guard let setting = SimulatedPermissions.Setting(rawValue: value) else {
          throw QAError("set= takes notAsked, denied or granted, not \"\(value)\"")
        }
        changes.append { simulated.set(permission, to: setting) }
      }
      for (permission, value) in try pairs("answer") {
        guard let answer = SimulatedPermissions.Answer(rawValue: value) else {
          throw QAError("answer= takes allow, deny or ignore, not \"\(value)\"")
        }
        changes.append { simulated.answer(permission, with: answer) }
      }
      for (permission, value) in try pairs("toggle") {
        guard ["on", "off"].contains(value) else { throw QAError("toggle= takes on or off, not \"\(value)\"") }
        changes.append { simulated.toggle(permission, on: value == "on") }
      }
      if let isOn = try flag("liveScreenRecording") {
        changes.append { simulated.setLiveScreenRecording(isOn) }
      }
      if let isOn = try flag("pasteboardAsks") {
        changes.append { simulated.setPasteboardAsks(isOn) }
      }
      if arguments["refresh"] != nil {
        changes.append { simulated.refresh() }
      }
      let known: Set<String> = ["set", "answer", "toggle", "liveScreenRecording", "pasteboardAsks", "refresh", "quitReopen", "required"]
      if let unknown = arguments.keys.first(where: { !known.contains($0) }) {
        throw QAError("perm knows \(known.sorted().joined(separator: ", ")), not \(unknown)")
      }
      for change in changes {
        change()
      }
      save()
      QALog.record("permissions", "perm", arguments)
    }

    static var names: String { Permission.allCases.map(\.rawValue).joined(separator: ", ") }

    /// `press=turnOn [permission=]` or `press=restart` on a feature's permission settings row (`PermissionRows`).
    /// Refused while the row doesn't show that button, as a user couldn't press it; returns false for other presses.
    @MainActor
    public static func pressRow(
      _ arguments: [String: String],
      needs: [PermissionNeed],
      statuses: [Permission: PermissionStatus],
      turnOn: (Permission) -> Void,
      restart: () -> Void
    ) throws -> Bool {
      let wanted: PermissionMark
      switch arguments["press"] {
      case "turnOn": wanted = .warning
      case "restart": wanted = .afterRestart
      default: return false
      }
      let permission: Permission
      if let name = arguments["permission"] {
        guard let named = Permission(rawValue: name) else { throw QAError("permission= takes one of \(names), not \(name)") }
        permission = named
      } else {
        guard let first = needs.first?.permission else { throw QAError("this feature has no permission row") }
        permission = first
      }
      guard needs.contains(where: { $0.permission == permission }),
            PermissionMark(statuses[permission]) == wanted
      else {
        throw QAError("no \(wanted == .warning ? "Turn on" : "Restart Vortex") shows in the \(permission.rawValue) row now")
      }
      if wanted == .warning { turnOn(permission) } else { restart() }
      return true
    }

    /// What the state dump shows: what the app read, what System Settings holds, the answers and flags, and the
    /// prompts and panes macOS showed.
    public struct Snapshot: Encodable {
      var statuses: [Permission: PermissionStatus]
      var settings: [Permission: SimulatedPermissions.Setting]
      var settingsAtLaunch: [Permission: SimulatedPermissions.Setting]
      var answers: [Permission: SimulatedPermissions.Answer]
      var requested: [Permission]
      var liveScreenRecording: Bool
      var pasteboardAsks: Bool
      var frequentChecks: Bool
      var events: [String]
    }

    public static var snapshot: Snapshot {
      let state = simulated.state
      return Snapshot(
        statuses: simulated.statuses,
        settings: state.settings,
        settingsAtLaunch: state.settingsAtLaunch,
        answers: state.answers,
        requested: state.requested.map(\.rawValue).sorted().compactMap(Permission.init(rawValue:)),
        liveScreenRecording: state.liveScreenRecording,
        pasteboardAsks: state.pasteboardAsks,
        frequentChecks: state.frequentChecks,
        events: state.events.map { event in
          switch event {
          case let .prompt(permission): "prompt \(permission.rawValue)"
          case let .settings(permission): "settings \(permission.rawValue)"
          case .relaunch: "relaunch"
          }
        }
      )
    }
  }
#endif
