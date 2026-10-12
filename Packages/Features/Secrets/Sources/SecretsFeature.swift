import ComposableArchitecture
import Foundation
import GRDB
import os
import VortexCore
import VortexPlatform

/// What the form for a new key holds.
struct KeyDraft: Equatable, Sendable {
  enum Problem: Equatable, Sendable {
    case noValue
    case badName
    case nameTaken
    case notSaved
  }

  var name = ""
  var value = ""
  var note = ""
  var lifetime = KeyLifetime.forever
  /// The value in plain text, to check what was pasted; hidden again when the window closes.
  var showsValue = false
  /// Why it was not saved, shown under the fields.
  var problem: Problem?
  var isSaving = false

  var kind: KeyKind { KeyKind(value: value) }
}

/// A value the user asked to see, for a moment.
struct RevealedValue: Equatable, Sendable {
  let id: SecretKey.ID
  let value: String
}

/// Claude asked to use keys the user has not allowed in its session yet; the call waits for the answer.
struct Approval: Identifiable, Equatable, Sendable {
  let id: UUID
  let call: MCPCall
  /// The keys to allow, by name.
  let names: [String]
  let command: String
  let folder: String?
}

/// Keys Claude uses by name without ever seeing them. Values live in the keychain; Claude reaches them through the
/// local MCP server: `keys` lists them, `run` runs a command with {{name}} where a value goes and gets the output back
/// with the values taken out. The first use of a key in a session waits for «Дозволити», asked in the notch and in a
/// notification. A key can live an hour, until the end of the day or for good; deleting one can be taken back for a
/// moment. A key shows when a command last ran with it.
@Reducer
struct SecretsFeature: Sendable {
  static let id: FeatureID = "secrets"
  static let keychainService = "io.github.ortexisartem.vortex.keys"
  static let serverService = "io.github.ortexisartem.vortex.mcp"
  static let tokenAccount = "token"
  /// How long a deleted key can be taken back.
  static let undoTime: Duration = .seconds(5)
  /// How long a call waits for «Дозволити». With the longest command it stays under the 5 minutes Claude Code waits
  /// for an answer.
  static let answerTime: Duration = .seconds(90)
  /// How long a value stays shown.
  static let revealTime: Duration = .seconds(20)
  /// Seconds a command may run, unless Claude asks for other, within `timeouts`.
  static let defaultTimeout = 60
  static let timeouts = 1...180
  /// Each request's notification is this, a dot and the request's id, so its buttons answer that request.
  static let approvalNotificationPrefix = "secrets.approval"
  static let allowButtonID = "secrets.allow"
  static let denyButtonID = "secrets.deny"

  enum ServerStatus: Equatable, Sendable {
    case off
    case starting
    case listening(port: Int)
    case failed(String)
  }

  struct Session: Equatable, Sendable {
    var client: String
    /// Lowercased names allowed in it.
    var allowed: Set<String> = []
  }

  @ObservableState
  struct State: Equatable {
    var keys: IdentifiedArrayOf<SecretKey> = []
    var isLoaded = false
    var isEnabled = false
    /// The form for a new key, while it is open.
    var draft: KeyDraft?
    var revealed: RevealedValue?
    /// Deleted a moment ago: it can come back until `undoTime` is up.
    var deleted: SecretKey?
    /// By MCP session id.
    var sessions: [String: Session] = [:]
    var approvals: IdentifiedArrayOf<Approval> = []
    /// Commands running now, with the keys handed to them: they stop with the feature, and count as used once they ran.
    var running: [MCPCall.ID: [SecretKey.ID]] = [:]
    var server = ServerStatus.off
    var token: String?
    /// Grows with every approval asked for, so each one flashes the notch anew.
    var alarms = 0
    @Shared(.secretsSettings) var settings
    @Shared(.notchIndicators) var indicators

    init() {}

    /// What connects Claude Code once, for every project; an earlier connection, such as to another port, goes first,
    /// as `claude mcp add` refuses a name it has.
    var connectCommand: String? {
      token.map { token in
        "claude mcp remove --scope user vortex >/dev/null 2>&1; "
          + "claude mcp add --transport http --scope user vortex http://127.0.0.1:\(settings.port)/mcp "
          + "--header \"Authorization: Bearer \(token)\""
      }
    }

    /// The key `name` means, in any case; an expired one is none.
    func key(named name: String, at now: Date) -> SecretKey? {
      keys.first { $0.name.lowercased() == name.lowercased() && !$0.isExpired(at: now) }
    }

    /// A key and the names asked for in the notch, flashing, while an approval waits.
    var indicator: NotchIndicator? {
      guard isEnabled, let approval = approvals.first else { return nil }
      return NotchIndicator(
        leading: [.symbol("key.fill")],
        trailing: [.text(approval.names.joined(separator: ", "))],
        priority: 20,
        alarm: alarms
      )
    }
  }

  enum Action: Equatable, Sendable {
    case start
    case stop
    case loaded(keys: [SecretKey])
    case loadFailed
    case addTapped
    case draftChanged(KeyDraft)
    case saveTapped
    case cancelTapped
    case saved(SecretKey)
    case saveFailed
    /// Shows the value, or hides it again.
    case revealTapped(SecretKey.ID)
    case revealed(SecretKey.ID, String)
    case hideTapped
    /// The window closed, or the tab went out of view: whatever value shows goes out of sight.
    case windowClosed
    case copyValueTapped
    /// Copies «name (Vortex)»: enough for Claude, which learns the keys from Vortex.
    case copyNameTapped(SecretKey.ID)
    case deleteTapped(SecretKey.ID)
    case undoTapped
    case undoExpired
    case expiryReached
    case tokenReady(String)
    case server(MCPEvent)
    case approveTapped(Approval.ID)
    case denyTapped(Approval.ID)
    case approvalUnanswered(Approval.ID)
    case notificationButtonPressed(NotificationClient.Press)
    /// The command for a call ended; `ran` when it was started, not stopped before by a missing value or an error.
    case commandEnded(MCPCall.ID, ran: Bool)
    case copyConnectCommandTapped
    case portChanged(Int)
  }

  @Dependency(\.calendar) var calendar
  @Dependency(\.continuousClock) var clock
  @Dependency(\.commandClient) var commands
  @Dependency(\.database) var database
  @Dependency(\.databaseIsOnDisk) var databaseIsOnDisk
  @Dependency(\.date.now) var now
  @Dependency(\.keychainClient) var keychain
  @Dependency(\.notificationClient) var notifications
  @Dependency(\.pasteboardClient) var pasteboard
  @Dependency(\.mcpServer) var server
  @Dependency(\.uuid) var uuid

  private enum CancelID: Hashable {
    case load
    case token
    case server
    case buttons
    case expiry
    case undo
    case reveal
    case revealRead
    case answer(Approval.ID)
    /// Posting or taking back a request's notification: taking it back stops a post still on its way.
    case notification(Approval.ID)
    case run(MCPCall.ID)
    case deletion(SecretKey.ID)
  }

  init() {}

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .start:
        guard !state.isEnabled else { return .none }
        state.isEnabled = true
        state.server = .starting
        // Requests from before, such as a run Vortex quit in, are over: so are their notifications.
        guard state.isLoaded else { return .merge(load(), listenToNotificationButtons(), forgetNotifications()) }
        return .merge(expire(&state), startServing(state), listenToNotificationButtons(), forgetNotifications())

      case .stop:
        state.isEnabled = false
        state.server = .off
        return .merge(
          resetSessions(&state),
          .cancel(id: CancelID.load),
          .cancel(id: CancelID.token),
          .cancel(id: CancelID.server),
          .cancel(id: CancelID.buttons),
          .cancel(id: CancelID.expiry)
        )

      case let .loaded(keys):
        state.keys = IdentifiedArray(keys.sorted(by: Self.byName)) { first, _ in first }
        state.isLoaded = true
        // Only now: a call coming in sooner would find no keys.
        return .merge(expire(&state), startServing(state))

      case .loadFailed:
        state.isLoaded = true
        return startServing(state)

      case .addTapped:
        state.draft = KeyDraft()
        return .none

      case let .draftChanged(draft):
        guard let current = state.draft, !current.isSaving else { return .none }
        var draft = draft
        draft.problem = nil
        draft.isSaving = false
        state.draft = draft
        return .none

      case .saveTapped:
        return save(&state)

      case .cancelTapped:
        guard state.draft?.isSaving != true else { return .none }
        state.draft = nil
        return .none

      case let .saved(key):
        state.draft = nil
        state.keys.append(key)
        state.keys.sort(by: Self.byName)
        return scheduleExpiry(state)

      case .saveFailed:
        state.draft?.isSaving = false
        state.draft?.problem = .notSaved
        return .none

      case let .revealTapped(id):
        if state.revealed?.id == id {
          state.revealed = nil
          return .cancel(id: CancelID.reveal)
        }
        // No Touch ID: on an unlocked Mac the value could be had through Claude anyway, so it would only be in the way.
        guard state.keys[id: id] != nil else { return .none }
        return .run { send in
          guard let value = try await keychain.read(Self.keychainService, id.uuidString) else { return }
          await send(.revealed(id, value))
        } catch: { error, _ in
          logger.error("Reading a key failed: \(error, privacy: .public)")
        }
        .cancellable(id: CancelID.revealRead, cancelInFlight: true)

      case let .revealed(id, value):
        guard state.keys[id: id] != nil else { return .none }
        state.revealed = RevealedValue(id: id, value: value)
        return .run { send in
          try await clock.sleep(for: Self.revealTime)
          await send(.hideTapped)
        }
        .cancellable(id: CancelID.reveal, cancelInFlight: true)

      case .hideTapped:
        state.revealed = nil
        return .merge(.cancel(id: CancelID.reveal), .cancel(id: CancelID.revealRead))

      case .windowClosed:
        state.revealed = nil
        state.draft?.showsValue = false
        return .merge(.cancel(id: CancelID.reveal), .cancel(id: CancelID.revealRead))

      case .copyValueTapped:
        guard let value = state.revealed?.value else { return .none }
        // Marked concealed: clipboard histories, Vortex's own too, leave it out.
        return .run { _ in await pasteboard.write(.text(value), true, nil) }

      case let .copyNameTapped(id):
        guard let key = state.keys[id: id] else { return .none }
        let text = "\(key.name) (Vortex)"
        return .run { _ in await pasteboard.write(.text(text), false, nil) }

      case let .deleteTapped(id):
        guard let key = state.keys.remove(id: id) else { return .none }
        if state.revealed?.id == id { state.revealed = nil }
        let settled = settleDeleted(&state)
        state.deleted = key
        return .merge(
          settled,
          .run { _ in
            try await database.write { db in _ = try key.delete(db) }
          } catch: { error, _ in
            guard !(error is CancellationError) else { return }
            logger.error("Deleting a key failed: \(error, privacy: .public)")
          }
          .cancellable(id: CancelID.deletion(key.id)),
          .run { send in
            try await clock.sleep(for: Self.undoTime)
            await send(.undoExpired)
          }
          .cancellable(id: CancelID.undo, cancelInFlight: true),
          scheduleExpiry(state)
        )

      case .undoTapped:
        guard let key = state.deleted else { return .none }
        state.deleted = nil
        state.keys.append(key)
        state.keys.sort(by: Self.byName)
        return .merge(
          .cancel(id: CancelID.undo),
          // Taken back before the row went: it stays.
          .cancel(id: CancelID.deletion(key.id)),
          .run { _ in
            try await database.write { db in try key.insert(db, onConflict: .replace) }
          } catch: { error, _ in
            logger.error("Taking a key back failed: \(error, privacy: .public)")
          },
          scheduleExpiry(state)
        )

      case .undoExpired:
        return settleDeleted(&state)

      case .expiryReached:
        return expire(&state)

      case let .tokenReady(token):
        state.token = token
        return serve(state)

      case let .server(event):
        return serverEvent(event, &state)

      case let .approveTapped(id):
        guard let approval = state.approvals.remove(id: id) else { return .none }
        syncIndicator(&state)
        let answered = Effect<Action>.merge(.cancel(id: CancelID.answer(id)), forgetNotification(id))
        guard state.sessions[approval.call.session] != nil else { return answered }
        state.sessions[approval.call.session]?.allowed.formUnion(approval.names.map { $0.lowercased() })
        return .merge(answered, run(approval.call, &state))

      case let .denyTapped(id):
        return turnDown(id, because: .denied, &state)

      case let .approvalUnanswered(id):
        return turnDown(id, because: .unanswered, &state)

      case let .notificationButtonPressed(press):
        // The request the notification shows, whatever came in since.
        let prefix = Self.approvalNotificationPrefix + "."
        guard press.notification.hasPrefix(prefix),
              let id = UUID(uuidString: String(press.notification.dropFirst(prefix.count))),
              state.approvals[id: id] != nil
        else { return .none }
        switch press.button {
        case Self.allowButtonID: return .send(.approveTapped(id))
        case Self.denyButtonID: return .send(.denyTapped(id))
        default: return .none
        }

      case let .commandEnded(call, ran):
        guard let used = state.running.removeValue(forKey: call), ran else { return .none }
        return markUsed(used, &state)

      case .copyConnectCommandTapped:
        guard let command = state.connectCommand else { return .none }
        // It holds the token: marked concealed, so clipboard histories leave it out.
        return .run { _ in await pasteboard.write(.text(command), true, nil) }

      case let .portChanged(port):
        guard SecretsSettings.ports.contains(port), port != state.settings.port else { return .none }
        state.$settings.withLock { $0.port = port }
        let reset = resetSessions(&state)
        guard state.isEnabled else { return reset }
        state.server = .starting
        return .merge(reset, serve(state))
      }
    }
  }

  private static func byName(_ lhs: SecretKey, _ rhs: SecretKey) -> Bool {
    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
  }

  // MARK: - Keys

  private func save(_ state: inout State) -> Effect<Action> {
    guard var draft = state.draft, !draft.isSaving else { return .none }
    let value = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
    var name = draft.name.trimmingCharacters(in: .whitespaces)
    if name.isEmpty { name = freeName(for: KeyKind(value: value), in: state) }
    if value.isEmpty {
      draft.problem = .noValue
    } else if !SecretKey.isValidName(name) {
      draft.problem = .badName
    } else if state.keys.contains(where: { $0.name.lowercased() == name.lowercased() }) {
      draft.problem = .nameTaken
    }
    guard draft.problem == nil else {
      state.draft = draft
      return .none
    }
    draft.isSaving = true
    state.draft = draft
    let key = SecretKey(
      id: uuid(),
      name: name,
      kind: KeyKind(value: value),
      note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
      createdAt: now,
      expiresAt: draft.lifetime.expiry(from: now, calendar: calendar),
      lastUsedAt: nil
    )
    // A new change makes the deletion before it final.
    let settled = settleDeleted(&state)
    return .merge(
      settled,
      .run { send in
        // The value first: a row without one would be a key that can't be used. A value left without a row is
        // deleted at the next launch.
        try await keychain.save(Self.keychainService, key.id.uuidString, value, "Vortex: \(key.name)")
        try await database.write { db in try key.insert(db) }
        await send(.saved(key))
      } catch: { error, send in
        logger.error("Saving a key failed: \(error, privacy: .public)")
        await send(.saveFailed)
      }
    )
  }

  /// `kind`'s name, numbered when it is taken.
  private func freeName(for kind: KeyKind, in state: State) -> String {
    let taken = Set(state.keys.map { $0.name.lowercased() })
    let base = kind.suggestedName
    guard taken.contains(base) else { return base }
    return (2...).lazy.map { "\(base)-\($0)" }.first { !taken.contains($0) } ?? base
  }

  /// The key deleted a moment ago can't come back any more: its value leaves the keychain.
  private func settleDeleted(_ state: inout State) -> Effect<Action> {
    guard let key = state.deleted else { return .none }
    state.deleted = nil
    return .merge(
      .cancel(id: CancelID.undo),
      .run { _ in await keychain.delete(Self.keychainService, key.id.uuidString) }
    )
  }

  /// Expired keys go, rows and values, and the next expiry is waited for.
  private func expire(_ state: inout State) -> Effect<Action> {
    let expired = state.keys.filter { $0.isExpired(at: now) }
    for key in expired {
      state.keys.remove(id: key.id)
      if state.revealed?.id == key.id { state.revealed = nil }
    }
    guard !expired.isEmpty else { return scheduleExpiry(state) }
    return .merge(
      .run { [expired = Array(expired)] _ in
        try await database.write { db in
          for key in expired {
            _ = try key.delete(db)
          }
        }
        for key in expired {
          await keychain.delete(Self.keychainService, key.id.uuidString)
        }
      } catch: { error, _ in
        logger.error("Deleting expired keys failed: \(error, privacy: .public)")
      },
      scheduleExpiry(state)
    )
  }

  private func scheduleExpiry(_ state: State) -> Effect<Action> {
    guard state.isEnabled, let next = state.keys.compactMap(\.expiresAt).min() else {
      return .cancel(id: CancelID.expiry)
    }
    let wait = max(next.timeIntervalSince(now), 0)
    return .run { send in
      try await clock.sleep(for: .milliseconds(Int(wait * 1000) + 100))
      await send(.expiryReached)
    }
    .cancellable(id: CancelID.expiry, cancelInFlight: true)
  }

  private func load() -> Effect<Action> {
    .run { [databaseIsOnDisk] send in
      try await database.migrate(SecretKey.migrator)
      let (keys, rowIDs) = try await database.read { db in
        (try SecretKey.fetchAllReadable(db), try String.fetchSet(db, sql: "SELECT id FROM \(SecretKey.databaseTableName)"))
      }
      // Values whose key is gone: Vortex stopped between saving a value and its row, or while a deletion could still
      // be taken back. Not while the database is only in memory: its file didn't open, and the keychain then holds the
      // only copy of every value.
      if databaseIsOnDisk {
        for account in await keychain.accounts(Self.keychainService) where !rowIDs.contains(account) {
          await keychain.delete(Self.keychainService, account)
        }
      }
      await send(.loaded(keys: keys))
    } catch: { error, send in
      logger.error("Loading the keys failed: \(error, privacy: .public)")
      await send(.loadFailed)
    }
    .cancellable(id: CancelID.load, cancelInFlight: true)
  }

  // MARK: - Claude

  private func startServing(_ state: State) -> Effect<Action> {
    guard state.isEnabled else { return .none }
    return state.token == nil ? prepareToken() : serve(state)
  }

  /// The server's token from the keychain; made the first time, from two random UUIDs.
  private func prepareToken() -> Effect<Action> {
    .run { send in
      if let token = try await keychain.read(Self.serverService, Self.tokenAccount) {
        await send(.tokenReady(token))
        return
      }
      let token = (uuid().uuidString + uuid().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
      try await keychain.save(Self.serverService, Self.tokenAccount, token, "Vortex: MCP token")
      await send(.tokenReady(token))
    } catch: { error, send in
      logger.error("Preparing the MCP token failed: \(error, privacy: .public)")
      await send(.server(.failed(String(describing: error))))
    }
    .cancellable(id: CancelID.token, cancelInFlight: true)
  }

  private func serve(_ state: State) -> Effect<Action> {
    guard state.isEnabled, let token = state.token else { return .none }
    let port = state.settings.port
    return .run { send in
      for await event in server.serve(port, token) {
        await send(.server(event))
      }
    }
    .cancellable(id: CancelID.server, cancelInFlight: true)
  }

  /// A new server, or none: sessions, the calls waiting in them and the commands running are over (the server answers
  /// the calls).
  private func resetSessions(_ state: inout State) -> Effect<Action> {
    let waiting = state.approvals.map(\.id)
    let running = Array(state.running.keys)
    state.sessions = [:]
    state.approvals = []
    syncIndicator(&state)
    return .merge(
      waiting.map { .cancel(id: CancelID.answer($0)) }
        + running.map { stopCommand($0, &state) }
        + [forgetNotifications()]
    )
  }

  private func serverEvent(_ event: MCPEvent, _ state: inout State) -> Effect<Action> {
    switch event {
    case let .listening(port):
      state.server = .listening(port: port)
      return .none
    case let .failed(message):
      state.server = .failed(message)
      return .none
    case let .sessionStarted(session):
      state.sessions[session.id] = Session(client: session.client)
      if !state.settings.hasConnected {
        state.$settings.withLock { $0.hasConnected = true }
      }
      return .none
    case let .sessionEnded(id):
      state.sessions[id] = nil
      let waiting = state.approvals.filter { $0.call.session == id }
      for approval in waiting {
        state.approvals.remove(id: approval.id)
      }
      syncIndicator(&state)
      return .merge(
        waiting.flatMap {
          [.cancel(id: CancelID.answer($0.id)), forgetNotification($0.id), reply($0.call, "The session ended.", isError: true)]
        }
      )
    case let .cancelled(call):
      // Waiting for «Дозволити»: the request goes; running: the command stops. Either way Claude gets «Cancelled.», also
      // when it gives a call up before its command got going.
      if let approval = state.approvals.first(where: { $0.call.id == call }) {
        return turnDown(approval.id, because: .cancelled, &state)
      }
      return stopCommand(call, &state)
    case let .call(call):
      switch call.tool {
      case .keys: return reply(call, keyList(state), isError: false)
      case .run: return run(call, &state)
      }
    }
  }

  private func keyList(_ state: State) -> String {
    let keys = state.keys.filter { !$0.isExpired(at: now) }
    guard !keys.isEmpty else { return "The user has no keys in Vortex yet; they add them in Vortex › Keys." }
    let lines = keys.map { key -> String in
      var line = "- {{\(key.name)}}: \(key.kind.summary)"
      if !key.note.isEmpty { line += ". The user's note: \(key.note)" }
      if let expiresAt = key.expiresAt { line += ". Expires \(expiresAt.formatted(.iso8601))" }
      return line
    }
    return "Keys in Vortex; in `run`, write {{name}} where a value goes:\n" + lines.joined(separator: "\n")
  }

  /// Runs the command when its keys are allowed in the session; otherwise asks the user first.
  private func run(_ call: MCPCall, _ state: inout State) -> Effect<Action> {
    guard let command = call.arguments["command"]?.string,
          !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return reply(call, "`command` is missing.", isError: true) }
    let prepared = KeyCommand(command)
    guard !prepared.names.isEmpty else {
      return reply(call, "Write {{name}} of a key where its value goes; run commands without keys in your own shell.", isError: true)
    }
    let unknown = prepared.names.filter { state.key(named: $0, at: now) == nil }
    guard unknown.isEmpty else {
      let known = state.keys.filter { !$0.isExpired(at: now) }.map { "{{\($0.name)}}" }
      let list = known.isEmpty ? "The user has no keys in Vortex." : "Keys: \(known.joined(separator: ", "))."
      return reply(call, "No key \(unknown.map { "{{\($0)}}" }.joined(separator: ", ")). \(list)", isError: true)
    }
    guard let session = state.sessions[call.session] else {
      return reply(call, "The session ended.", isError: true)
    }
    let asked = prepared.names.filter { !session.allowed.contains($0) }
    guard asked.isEmpty else {
      return ask(call, names: asked.compactMap { state.key(named: $0, at: now)?.name }, command: command, &state)
    }
    return execute(call, prepared, &state)
  }

  private func ask(_ call: MCPCall, names: [String], command: String, _ state: inout State) -> Effect<Action> {
    let approval = Approval(id: uuid(), call: call, names: names, command: command, folder: call.arguments["cwd"]?.string)
    state.approvals.append(approval)
    state.alarms += 1
    syncIndicator(&state)
    return .merge(
      notify(approval),
      .run { [id = approval.id] send in
        try await clock.sleep(for: Self.answerTime)
        await send(.approvalUnanswered(id))
      }
      .cancellable(id: CancelID.answer(approval.id), cancelInFlight: true)
    )
  }

  /// A notification of its own for `approval`, whose buttons answer it.
  private func notify(_ approval: Approval) -> Effect<Action> {
    let title = "\(approval.call.client) → \(approval.names.joined(separator: ", "))"
    // Its start; the tab shows all of it.
    let body = approval.command.count > 240 ? approval.command.prefix(239) + "…" : approval.command
    let buttons = [
      NotificationClient.Button(id: Self.allowButtonID, title: String(localized: "Allow", bundle: .module)),
      NotificationClient.Button(id: Self.denyButtonID, title: String(localized: "Deny", bundle: .module)),
    ]
    let id = Self.notificationID(approval.id)
    return .run { _ in
      guard await notifications.requestAuthorization() else { return }
      await notifications.post(id, title, body, buttons)
    }
    .cancellable(id: CancelID.notification(approval.id), cancelInFlight: true)
  }

  static func notificationID(_ approval: Approval.ID) -> String {
    "\(approvalNotificationPrefix).\(approval.uuidString)"
  }

  /// A request answered or gone: its notification goes, also one still on its way.
  private func forgetNotification(_ approval: Approval.ID) -> Effect<Action> {
    .merge(
      .cancel(id: CancelID.notification(approval)),
      .run { _ in await notifications.remove(Self.notificationID(approval)) }
    )
  }

  /// Every request's notification, this run's or a run's before.
  private func forgetNotifications() -> Effect<Action> {
    .run { _ in await notifications.remove(Self.approvalNotificationPrefix) }
  }

  private enum Refusal {
    case denied
    case unanswered
    case cancelled
  }

  private func turnDown(_ id: Approval.ID, because refusal: Refusal, _ state: inout State) -> Effect<Action> {
    guard let approval = state.approvals.remove(id: id) else { return .none }
    syncIndicator(&state)
    let names = approval.names.map { "{{\($0)}}" }.joined(separator: ", ")
    let text = switch refusal {
    case .denied: "The user did not allow \(names). Ask them before trying again."
    case .unanswered: "Nobody allowed \(names) in time; the user may be away."
    case .cancelled: "Cancelled."
    }
    return .merge(.cancel(id: CancelID.answer(id)), forgetNotification(id), reply(approval.call, text, isError: true))
  }

  private func execute(_ call: MCPCall, _ prepared: KeyCommand, _ state: inout State) -> Effect<Action> {
    let keys = prepared.names.compactMap { state.key(named: $0, at: now) }
    let folder = call.arguments["cwd"]?.string.map { URL(fileURLWithPath: $0, isDirectory: true) }
    let timeout = min(max(call.arguments["timeout"]?.int ?? Self.defaultTimeout, Self.timeouts.lowerBound), Self.timeouts.upperBound)
    state.running[call.id] = keys.map(\.id)
    return .run { send in
      var byName: [String: String] = [:]
      for key in keys {
        guard let value = try await keychain.read(Self.keychainService, key.id.uuidString) else {
          let text = "The value of {{\(key.name)}} is gone from the keychain; the user has to add the key again."
          await server.reply(call.id, MCPToolResult(text: text, isError: true))
          await send(.commandEnded(call.id, ran: false))
          return
        }
        byName[key.name] = value
      }
      let values = Dictionary(byName.map { ($0.key.lowercased(), $0.value) }) { first, _ in first }
      let output = try await commands.run(prepared.shellCommand, folder, prepared.environment(values: values), .seconds(timeout))
      // Given up meanwhile: Claude got «Cancelled.» and the keys count as used already.
      guard !Task.isCancelled else { return }
      await send(.commandEnded(call.id, ran: true))
      let report = KeyCommand.report(output, values: byName, timeout: timeout)
      await server.reply(call.id, MCPToolResult(text: report, isError: output.exitCode != 0))
    } catch: { error, send in
      await server.reply(call.id, MCPToolResult(text: "Vortex could not run the command: \(error)", isError: true))
      await send(.commandEnded(call.id, ran: false))
    }
    .cancellable(id: CancelID.run(call.id))
  }

  /// A running command Claude gave up, or one the feature stops: it stops, Claude gets «Cancelled.», and its keys count
  /// as used, as it ran with them.
  private func stopCommand(_ call: MCPCall.ID, _ state: inout State) -> Effect<Action> {
    let used = state.running.removeValue(forKey: call) ?? []
    return .merge(
      .cancel(id: CancelID.run(call)),
      .run { _ in await server.reply(call, MCPToolResult(text: "Cancelled.", isError: true)) },
      markUsed(used, &state)
    )
  }

  private func reply(_ call: MCPCall, _ text: String, isError: Bool) -> Effect<Action> {
    .run { _ in await server.reply(call.id, MCPToolResult(text: text, isError: isError)) }
  }

  /// The keys a command ran with: when, shown on their rows and kept.
  private func markUsed(_ ids: [SecretKey.ID], _ state: inout State) -> Effect<Action> {
    guard !ids.isEmpty else { return .none }
    let usedAt = now
    for id in ids { state.keys[id: id]?.lastUsedAt = usedAt }
    return .run { _ in
      try await database.write { db in
        for id in ids {
          try db.execute(
            sql: "UPDATE \(SecretKey.databaseTableName) SET lastUsedAt = ? WHERE id = ?",
            arguments: [usedAt, id.uuidString]
          )
        }
      }
    } catch: { error, _ in
      logger.error("Marking keys used failed: \(error, privacy: .public)")
    }
  }

  private func syncIndicator(_ state: inout State) {
    let indicator = state.indicator
    guard state.indicators[Self.id] != indicator else { return }
    state.$indicators.withLock { $0[Self.id] = indicator }
  }

  private func listenToNotificationButtons() -> Effect<Action> {
    .run { send in
      for await press in await notifications.buttonPresses() {
        await send(.notificationButtonPressed(press))
      }
    }
    .cancellable(id: CancelID.buttons, cancelInFlight: true)
  }
}

private let logger = Logger(subsystem: "io.github.ortexisartem.vortex", category: "secrets")
