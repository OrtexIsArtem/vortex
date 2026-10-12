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
/// moment. Every use is logged.
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
  static let approvalNotificationID = "secrets.approval"
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
    /// The latest uses, newest first.
    var uses: [KeyUse] = []
    var isLoaded = false
    var isEnabled = false
    var showsLog = false
    /// The form for a new key, while it is open.
    var draft: KeyDraft?
    var revealed: RevealedValue?
    /// Deleted a moment ago: it can come back until `undoTime` is up.
    var deleted: SecretKey?
    /// By MCP session id.
    var sessions: [String: Session] = [:]
    var approvals: IdentifiedArrayOf<Approval> = []
    /// The approval the notification shows, which its buttons answer.
    var notifiedApproval: Approval.ID?
    /// Commands running now, by call: the log keeps one Claude gives up as cancelled.
    var running: [MCPCall.ID: KeyUse] = [:]
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
    case loaded(keys: [SecretKey], uses: [KeyUse])
    case loadFailed
    case logToggled
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
    case copyValueTapped
    case deleteTapped(SecretKey.ID)
    case undoTapped
    case undoExpired
    case expiryReached
    case tokenReady(String)
    case server(MCPEvent)
    case approveTapped(Approval.ID)
    case denyTapped(Approval.ID)
    case approvalUnanswered(Approval.ID)
    case notificationButtonPressed(String)
    case used(KeyUse)
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
    case answer(Approval.ID)
    /// Posting or removing the notification: the newest wins, so it never shows a request other than the one its
    /// buttons answer.
    case notification
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
        guard state.isLoaded else { return .merge(load(), listenToNotificationButtons()) }
        return .merge(expire(&state), startServing(state), listenToNotificationButtons())

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

      case let .loaded(keys, uses):
        state.keys = IdentifiedArray(keys.sorted(by: Self.byName)) { first, _ in first }
        state.uses = uses
        state.isLoaded = true
        // Only now: a call coming in sooner would find no keys.
        return .merge(expire(&state), startServing(state))

      case .loadFailed:
        state.isLoaded = true
        return startServing(state)

      case .logToggled:
        state.showsLog.toggle()
        if state.showsLog { state.draft = nil }
        return .none

      case .addTapped:
        state.draft = KeyDraft()
        state.showsLog = false
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
        return .cancel(id: CancelID.reveal)

      case .copyValueTapped:
        guard let value = state.revealed?.value else { return .none }
        // Marked concealed: clipboard histories, Vortex's own too, leave it out.
        return .run { _ in await pasteboard.write(.text(value), true, nil) }

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
        let next = renotify(&state)
        guard state.sessions[approval.call.session] != nil else { return .merge(.cancel(id: CancelID.answer(id)), next) }
        state.sessions[approval.call.session]?.allowed.formUnion(approval.names.map { $0.lowercased() })
        return .merge(.cancel(id: CancelID.answer(id)), next, run(approval.call, &state))

      case let .denyTapped(id):
        return turnDown(id, outcome: .denied, &state)

      case let .approvalUnanswered(id):
        return turnDown(id, outcome: .unanswered, &state)

      case let .notificationButtonPressed(button):
        guard let id = state.notifiedApproval, state.approvals[id: id] != nil else { return .none }
        switch button {
        case Self.allowButtonID: return .send(.approveTapped(id))
        case Self.denyButtonID: return .send(.denyTapped(id))
        default: return .none
        }

      case let .used(use):
        // Not when it is logged already: Claude gave it up before the command got going.
        guard state.running.contains(where: { $0.value.id == use.id }) else { return .none }
        state.running = state.running.filter { $0.value.id != use.id }
        return record(use, &state)

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
      let oldest = calendar.date(byAdding: .day, value: -KeyUse.keptDays, to: now) ?? now
      let (keys, uses, rowIDs) = try await database.write { db in
        try db.execute(sql: "DELETE FROM \(KeyUse.databaseTableName) WHERE at < ?", arguments: [oldest])
        return (
          try SecretKey.fetchAllReadable(db),
          try KeyUse.latest(db),
          try String.fetchSet(db, sql: "SELECT id FROM \(SecretKey.databaseTableName)")
        )
      }
      // Values whose key is gone: Vortex stopped between saving a value and its row, or while a deletion could still
      // be taken back. Not while the database is only in memory: its file didn't open, and the keychain then holds the
      // only copy of every value.
      if databaseIsOnDisk {
        for account in await keychain.accounts(Self.keychainService) where !rowIDs.contains(account) {
          await keychain.delete(Self.keychainService, account)
        }
      }
      await send(.loaded(keys: keys, uses: uses))
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

  /// A new server, or none: sessions and the calls waiting in them are over (the server answers those calls).
  private func resetSessions(_ state: inout State) -> Effect<Action> {
    let waiting = state.approvals.map(\.id)
    state.sessions = [:]
    state.approvals = []
    state.notifiedApproval = nil
    syncIndicator(&state)
    return .merge(waiting.map { .cancel(id: CancelID.answer($0)) } + [removeNotification()])
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
      return .merge(
        waiting.flatMap { [.cancel(id: CancelID.answer($0.id)), reply($0.call, "The session ended.", isError: true)] }
          + [renotify(&state)]
      )
    case let .cancelled(call):
      // Waiting for «Дозволити»: the request goes; running: the command stops. Either way Claude gets «Cancelled.» and
      // the log keeps it; a command that ran counts as a use of its keys.
      if let approval = state.approvals.first(where: { $0.call.id == call }) {
        return turnDown(approval.id, outcome: .cancelled, &state)
      }
      guard var use = state.running.removeValue(forKey: call) else { return .cancel(id: CancelID.run(call)) }
      use.outcome = .cancelled
      return .merge(
        .cancel(id: CancelID.run(call)),
        .run { _ in await server.reply(call, MCPToolResult(text: "Cancelled.", isError: true)) },
        record(use, ranWithKeys: true, &state)
      )
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
    return execute(call, prepared, command: command, &state)
  }

  private func ask(_ call: MCPCall, names: [String], command: String, _ state: inout State) -> Effect<Action> {
    let approval = Approval(id: uuid(), call: call, names: names, command: command, folder: call.arguments["cwd"]?.string)
    state.approvals.append(approval)
    state.alarms += 1
    return .merge(
      notify(approval, &state),
      .run { [id = approval.id] send in
        try await clock.sleep(for: Self.answerTime)
        await send(.approvalUnanswered(id))
      }
      .cancellable(id: CancelID.answer(approval.id), cancelInFlight: true)
    )
  }

  /// The notification shows `approval`, and its buttons answer it.
  private func notify(_ approval: Approval, _ state: inout State) -> Effect<Action> {
    state.notifiedApproval = approval.id
    syncIndicator(&state)
    let title = "\(approval.call.client) → \(approval.names.joined(separator: ", "))"
    // Its start; the tab shows all of it.
    let body = approval.command.count > 240 ? approval.command.prefix(239) + "…" : approval.command
    let buttons = [
      NotificationClient.Button(id: Self.allowButtonID, title: String(localized: "Allow", bundle: .module)),
      NotificationClient.Button(id: Self.denyButtonID, title: String(localized: "Deny", bundle: .module)),
    ]
    return .run { _ in
      guard await notifications.requestAuthorization() else { return }
      await notifications.post(Self.approvalNotificationID, title, body, buttons)
    }
    .cancellable(id: CancelID.notification, cancelInFlight: true)
  }

  private func removeNotification() -> Effect<Action> {
    .run { _ in await notifications.remove(Self.approvalNotificationID) }
      .cancellable(id: CancelID.notification, cancelInFlight: true)
  }

  /// One request answered: the notification moves to the next one still waiting, if any.
  private func renotify(_ state: inout State) -> Effect<Action> {
    if let notified = state.notifiedApproval, state.approvals[id: notified] != nil {
      syncIndicator(&state)
      return .none
    }
    state.notifiedApproval = nil
    guard let next = state.approvals.first else {
      syncIndicator(&state)
      return removeNotification()
    }
    return notify(next, &state)
  }

  private func turnDown(_ id: Approval.ID, outcome: KeyUse.Outcome, _ state: inout State) -> Effect<Action> {
    guard let approval = state.approvals.remove(id: id) else { return .none }
    let next = renotify(&state)
    let names = approval.names.map { "{{\($0)}}" }.joined(separator: ", ")
    let text = switch outcome {
    case .denied: "The user did not allow \(names). Ask them before trying again."
    case .unanswered: "Nobody allowed \(names) in time; the user may be away."
    default: "Cancelled."
    }
    let use = KeyUse(
      id: uuid(),
      at: now,
      keys: approval.names,
      client: approval.call.client,
      command: approval.command,
      outcome: outcome,
      exitCode: nil
    )
    return .merge(.cancel(id: CancelID.answer(id)), next, reply(approval.call, text, isError: true), record(use, &state))
  }

  private func execute(_ call: MCPCall, _ prepared: KeyCommand, command: String, _ state: inout State) -> Effect<Action> {
    let keys = prepared.names.compactMap { state.key(named: $0, at: now) }
    let folder = call.arguments["cwd"]?.string.map { URL(fileURLWithPath: $0, isDirectory: true) }
    let timeout = min(max(call.arguments["timeout"]?.int ?? Self.defaultTimeout, Self.timeouts.lowerBound), Self.timeouts.upperBound)
    let use = KeyUse(
      id: uuid(),
      at: now,
      keys: keys.map(\.name),
      client: call.client,
      command: command,
      outcome: .failed,
      exitCode: nil
    )
    state.running[call.id] = use
    return .run { send in
      var byName: [String: String] = [:]
      for key in keys {
        guard let value = try await keychain.read(Self.keychainService, key.id.uuidString) else {
          let text = "The value of {{\(key.name)}} is gone from the keychain; the user has to add the key again."
          await server.reply(call.id, MCPToolResult(text: text, isError: true))
          await send(.used(use))
          return
        }
        byName[key.name] = value
      }
      let values = Dictionary(byName.map { ($0.key.lowercased(), $0.value) }) { first, _ in first }
      let output = try await commands.run(prepared.shellCommand, folder, prepared.environment(values: values), .seconds(timeout))
      let report = KeyCommand.report(output, values: byName, timeout: timeout)
      await server.reply(call.id, MCPToolResult(text: report, isError: output.exitCode != 0))
      var ran = use
      ran.outcome = output.timedOut ? .timedOut : .ran
      ran.exitCode = Int(output.exitCode)
      await send(.used(ran))
    } catch: { error, send in
      await server.reply(call.id, MCPToolResult(text: "Vortex could not run the command: \(error)", isError: true))
      await send(.used(use))
    }
    .cancellable(id: CancelID.run(call.id))
  }

  private func reply(_ call: MCPCall, _ text: String, isError: Bool) -> Effect<Action> {
    .run { _ in await server.reply(call.id, MCPToolResult(text: text, isError: isError)) }
  }

  /// Into the log, newest first; a use that ran marks its keys as used.
  private func record(_ use: KeyUse, ranWithKeys: Bool? = nil, _ state: inout State) -> Effect<Action> {
    state.uses.insert(use, at: 0)
    if state.uses.count > KeyUse.shown { state.uses.removeLast(state.uses.count - KeyUse.shown) }
    var used: [SecretKey.ID] = []
    if ranWithKeys ?? (use.outcome == .ran || use.outcome == .timedOut) {
      for name in use.keys {
        guard let key = state.keys.first(where: { $0.name == name }) else { continue }
        state.keys[id: key.id]?.lastUsedAt = use.at
        used.append(key.id)
      }
    }
    return .run { [used] _ in
      try await database.write { db in
        try use.insert(db)
        for id in used {
          try db.execute(
            sql: "UPDATE \(SecretKey.databaseTableName) SET lastUsedAt = ? WHERE id = ?",
            arguments: [use.at, id.uuidString]
          )
        }
      }
    } catch: { error, _ in
      logger.error("Logging a key use failed: \(error, privacy: .public)")
    }
  }

  private func syncIndicator(_ state: inout State) {
    let indicator = state.indicator
    guard state.indicators[Self.id] != indicator else { return }
    state.$indicators.withLock { $0[Self.id] = indicator }
  }

  private func listenToNotificationButtons() -> Effect<Action> {
    .run { send in
      for await button in await notifications.buttonPresses() {
        await send(.notificationButtonPressed(button))
      }
    }
    .cancellable(id: CancelID.buttons, cancelInFlight: true)
  }
}

private let logger = Logger(subsystem: "io.github.ortexisartem.vortex", category: "secrets")
