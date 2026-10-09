import ComposableArchitecture
import Foundation
import GRDB
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureSecrets

@MainActor
struct SecretsFeatureTests {
  let clock = TestClock()
  let now = LockIsolated(Date(timeIntervalSinceReferenceDate: 800_000_000))
  let database = VortexDatabase.inMemory()
  /// The keychain, by service and account.
  let keychain = LockIsolated<[String: String]>([:])
  let ran = LockIsolated<[(command: String, environment: [String: String], folder: String?)]>([])
  let replies = LockIsolated<[MCPToolResult]>([])
  let posted = LockIsolated<[String]>([])
  let copied = LockIsolated<[(text: String, concealed: Bool)]>([])
  let events = AsyncStream.makeStream(of: MCPEvent.self)
  let session = MCPSession(id: "s1", client: "Claude Code")
  let value = "postgres://admin:hunter2secret@db.example.com/app"

  func makeStore() -> TestStoreOf<SecretsFeature> {
    let store = TestStore(initialState: SecretsFeature.State()) {
      SecretsFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.date = DateGenerator { [now] in now.value }
      $0.calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
      }()
      $0.uuid = .incrementing
      $0.database = database
      $0.keychainClient.save = { [keychain] service, account, value, _ in keychain.withValue { $0["\(service)/\(account)"] = value } }
      $0.keychainClient.read = { [keychain] service, account in keychain.value["\(service)/\(account)"] }
      $0.keychainClient.delete = { [keychain] service, account in keychain.withValue { $0["\(service)/\(account)"] = nil } }
      $0.keychainClient.accounts = { [keychain] service in
        keychain.value.keys.filter { $0.hasPrefix(service + "/") }.map { String($0.dropFirst(service.count + 1)) }
      }
      $0.authenticationClient.confirmOwner = { _ in true }
      $0.commandClient.run = { [ran] command, folder, environment, _ in
        ran.withValue { $0.append((command, environment, folder?.path)) }
        // Prints the value, as a careless command might.
        return CommandClient.Output(exitCode: 0, stdout: Data("connected with \(environment["VORTEX_KEY_1"] ?? "")\n".utf8))
      }
      $0.mcpServer.serve = { [events] _, _ in events.stream }
      $0.mcpServer.reply = { [replies] _, result in replies.withValue { $0.append(result) } }
      $0.notificationClient.requestAuthorization = { true }
      $0.notificationClient.post = { [posted] id, title, _, _ in posted.withValue { $0.append("\(id): \(title)") } }
      $0.notificationClient.buttonPresses = { AsyncStream { _ in } }
      $0.pasteboardClient.write = { [copied] content, concealed, _ in
        if case let .text(text) = content { copied.withValue { $0.append((text, concealed)) } }
      }
    }
    store.exhaustivity = .off
    return store
  }

  func call(_ tool: MCPProtocol.Tool, _ arguments: JSONValue = [:], id: Int = 1) -> MCPCall {
    MCPCall(id: UUID(id), session: session.id, client: session.client, tool: tool, arguments: arguments)
  }

  /// Turns on the feature with the server listening and Claude Code connected.
  func start(_ store: TestStoreOf<SecretsFeature>) async {
    await store.send(.start)
    await store.receive(\.loaded)
    await store.receive(\.tokenReady)
    events.continuation.yield(.listening(port: 47823))
    await store.receive(\.server.listening)
    events.continuation.yield(.sessionStarted(session))
    await store.receive(\.server.sessionStarted)
  }

  func addKey(_ store: TestStoreOf<SecretsFeature>, name: String = "prod-db", note: String = "") async {
    await store.send(.addTapped)
    await store.send(.draftChanged(KeyDraft(name: name, value: value, note: note)))
    await store.send(.saveTapped)
    await store.receive(\.saved)
  }

  func eventually(_ condition: @escaping @Sendable () async throws -> Bool) async throws {
    for _ in 0..<100 where !(try await condition()) {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(try await condition())
  }

  @Test
  func valuesWithoutAKeyAreRemovedAtStart() async throws {
    let store = makeStore()
    await start(store)
    await addKey(store)
    let key = try #require(store.state.keys.first)
    await store.send(.stop)
    let orphan = "\(SecretsFeature.keychainService)/ORPHAN"
    keychain.withValue { $0[orphan] = "left by a crash" }

    let relaunched = makeStore()
    await relaunched.send(.start)
    await relaunched.receive(\.loaded)
    #expect(keychain.value[orphan] == nil)
    #expect(keychain.value["\(SecretsFeature.keychainService)/\(key.id.uuidString)"] == value)
    await relaunched.send(.stop)
  }

  @Test
  func noKeysMeansNoValueIsRemoved() async {
    // No keys may be a database that didn't open: the keychain then holds the only copy of every value.
    let account = "\(SecretsFeature.keychainService)/UNREAD"
    keychain.withValue { $0[account] = value }
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    #expect(keychain.value[account] == value)
    await store.send(.stop)
  }

  @Test
  func aKeysValueGoesToTheKeychainAndOnlyWhatItIsToTheDatabase() async throws {
    let store = makeStore()
    await start(store)
    #expect(store.state.token?.count == 64)
    #expect(store.state.connectCommand?.contains("http://127.0.0.1:47823/mcp") == true)
    await addKey(store, note: "bookings, read replica")
    let key = try #require(store.state.keys.first)
    #expect(key.name == "prod-db")
    #expect(key.kind == .postgres)
    #expect(key.expiresAt == nil)
    #expect(keychain.value["\(SecretsFeature.keychainService)/\(key.id.uuidString)"] == value)
    let saved = try await database.read { db in try SecretKey.fetchAllReadable(db) }
    #expect(saved == [key])
    #expect(try await database.read { db in try String.fetchAll(db, sql: "SELECT note FROM secrets_key") } == ["bookings, read replica"])
    await store.send(.stop)
  }

  @Test
  func aNameLeftEmptyComesFromTheKindAndABadOrTakenOneIsRefused() async throws {
    let store = makeStore()
    await start(store)
    await store.send(.addTapped)
    await store.send(.draftChanged(KeyDraft(name: "", value: value)))
    await store.send(.saveTapped)
    await store.receive(\.saved)
    #expect(store.state.keys.map(\.name) == ["postgres"])
    await store.send(.addTapped)
    await store.send(.draftChanged(KeyDraft(name: "Postgres", value: "other")))
    await store.send(.saveTapped)
    #expect(store.state.draft?.problem == .nameTaken)
    await store.send(.draftChanged(KeyDraft(name: "two words", value: "other")))
    await store.send(.saveTapped)
    #expect(store.state.draft?.problem == .badName)
    await store.send(.draftChanged(KeyDraft(name: "x", value: "  ")))
    await store.send(.saveTapped)
    #expect(store.state.draft?.problem == .noValue)
    await store.send(.stop)
  }

  @Test
  func claudeAsksTheFirstTimeAndOnceAllowedRunsWithoutSeeingTheValue() async throws {
    let store = makeStore()
    await start(store)
    await addKey(store)
    let first = call(.run, ["command": #"psql "{{prod-db}}" -c 'select 1'"#, "cwd": "/tmp"], id: 1)
    events.continuation.yield(.call(first))
    await store.receive(\.server.call)
    let approval = try #require(store.state.approvals.first)
    #expect(approval.names == ["prod-db"])
    #expect(store.state.indicators[SecretsFeature.id]?.trailing == [.text("prod-db")])
    #expect(ran.value.isEmpty)
    try await eventually { [posted] in posted.value == ["secrets.approval: Claude Code → prod-db"] }

    await store.send(.approveTapped(approval.id))
    await store.receive(\.used)
    #expect(ran.value.first?.command == #"psql "${VORTEX_KEY_1}" -c 'select 1'"#)
    #expect(ran.value.first?.environment == ["VORTEX_KEY_1": value])
    #expect(ran.value.first?.folder == "/tmp")
    #expect(replies.value.first == MCPToolResult(text: "exit code 0\nconnected with {{prod-db}}\n", isError: false))
    #expect(store.state.indicators[SecretsFeature.id] == nil)
    #expect(store.state.uses.first?.outcome == .ran)
    #expect(store.state.uses.first?.command == #"psql "{{prod-db}}" -c 'select 1'"#)
    #expect(store.state.keys.first?.lastUsedAt == now.value)

    // The same session runs it again without asking.
    events.continuation.yield(.call(call(.run, ["command": "echo {{PROD-DB}}"], id: 2)))
    await store.receive(\.server.call)
    await store.receive(\.used)
    #expect(store.state.approvals.isEmpty)
    #expect(ran.value.count == 2)
    let logged = try await database.read { db in try KeyUse.latest(db) }
    #expect(logged.count == 2)
    #expect(!logged.contains { $0.command.contains("hunter2secret") })
    await store.send(.stop)
  }

  @Test
  func aDeniedOrUnansweredRequestGetsAnErrorAndIsLogged() async throws {
    let store = makeStore()
    await start(store)
    await addKey(store)
    events.continuation.yield(.call(call(.run, ["command": "psql \"{{prod-db}}\""], id: 1)))
    await store.receive(\.server.call)
    await store.send(.denyTapped(try #require(store.state.approvals.first?.id)))
    try await eventually { [replies] in replies.value.count == 1 }
    #expect(replies.value.first?.isError == true)
    #expect(replies.value.first?.text.contains("did not allow {{prod-db}}") == true)
    #expect(store.state.uses.first?.outcome == .denied)

    events.continuation.yield(.call(call(.run, ["command": "psql \"{{prod-db}}\""], id: 2)))
    await store.receive(\.server.call)
    await clock.advance(by: SecretsFeature.answerTime)
    await store.receive(\.approvalUnanswered)
    #expect(store.state.approvals.isEmpty)
    #expect(store.state.uses.first?.outcome == .unanswered)
    #expect(ran.value.isEmpty)
    await store.send(.stop)
  }

  @Test
  func aRequestClaudeGivesUpGoesAwayAndTheNotificationMovesToTheNextOne() async throws {
    let store = makeStore()
    await start(store)
    await addKey(store)
    await addKey(store, name: "github")
    let first = call(.run, ["command": "psql \"{{prod-db}}\""], id: 1)
    let second = call(.run, ["command": "gh api user -H \"Authorization: Bearer {{github}}\""], id: 2)
    events.continuation.yield(.call(first))
    await store.receive(\.server.call)
    events.continuation.yield(.call(second))
    await store.receive(\.server.call)
    #expect(store.state.approvals.map(\.names) == [["prod-db"], ["github"]])
    #expect(store.state.notifiedApproval == store.state.approvals.last?.id)
    // Claude gives up the one the notification shows: it moves to the one still waiting.
    events.continuation.yield(.cancelled(second.id))
    await store.receive(\.server.cancelled)
    #expect(store.state.approvals.map(\.names) == [["prod-db"]])
    #expect(store.state.notifiedApproval == store.state.approvals.first?.id)
    try await eventually { [replies] in replies.value.contains(MCPToolResult(text: "Cancelled.", isError: true)) }
    try await eventually { [posted] in posted.value.last == "secrets.approval: Claude Code → prod-db" }
    #expect(store.state.indicators[SecretsFeature.id]?.trailing == [.text("prod-db")])
    await store.send(.stop)
  }

  @Test
  func unknownKeysAreNamedAndTheListShowsNoValue() async throws {
    let store = makeStore()
    await start(store)
    await addKey(store, note: "bookings")
    events.continuation.yield(.call(call(.run, ["command": "curl -H \"Authorization: Bearer {{github}}\" x"], id: 1)))
    await store.receive(\.server.call)
    events.continuation.yield(.call(call(.keys, id: 2)))
    await store.receive(\.server.call)
    try await eventually { [replies] in replies.value.count == 2 }
    #expect(replies.value.first == MCPToolResult(text: "No key {{github}}. Keys: {{prod-db}}.", isError: true))
    let list = try #require(replies.value.last?.text)
    #expect(list.contains("- {{prod-db}}: PostgreSQL connection URL (psql). The user's note: bookings"))
    #expect(!list.contains("hunter2secret"))
    #expect(store.state.approvals.isEmpty)
    await store.send(.stop)
  }

  @Test
  func aDeletedKeyComesBackWhileItCanAndThenItsValueGoes() async throws {
    let store = makeStore()
    await start(store)
    await addKey(store)
    let key = try #require(store.state.keys.first)
    let account = "\(SecretsFeature.keychainService)/\(key.id.uuidString)"
    await store.send(.deleteTapped(key.id))
    #expect(store.state.keys.isEmpty)
    #expect(keychain.value[account] == value)
    await store.send(.undoTapped)
    #expect(store.state.keys.map(\.id) == [key.id])
    try await eventually { try await self.database.read { db in try SecretKey.fetchAllReadable(db) }.count == 1 }
    await store.send(.deleteTapped(key.id))
    await clock.advance(by: SecretsFeature.undoTime)
    await store.receive(\.undoExpired)
    try await eventually { [keychain] in keychain.value[account] == nil }
    #expect(try await database.read { db in try SecretKey.fetchAllReadable(db) }.isEmpty)
    await store.send(.stop)
  }

  @Test
  func aKeyThatLivesAnHourDeletesItself() async throws {
    let store = makeStore()
    await start(store)
    await store.send(.addTapped)
    await store.send(.draftChanged(KeyDraft(name: "temp", value: value, lifetime: .hour)))
    await store.send(.saveTapped)
    await store.receive(\.saved)
    let key = try #require(store.state.keys.first)
    #expect(key.expiresAt == now.value.addingTimeInterval(3600))
    now.withValue { $0 += 3601 }
    await clock.advance(by: .seconds(3601))
    await store.receive(\.expiryReached)
    #expect(store.state.keys.isEmpty)
    try await eventually { [keychain] in keychain.value["\(SecretsFeature.keychainService)/\(key.id.uuidString)"] == nil }
    await store.send(.stop)
  }

  @Test
  func forClaudeCopiesAPhraseAndTheConnectCommandIsCopiedConcealed() async throws {
    let store = makeStore()
    await start(store)
    await addKey(store)
    await store.send(.copyForClaudeTapped(try #require(store.state.keys.first?.id)))
    await store.send(.copyConnectCommandTapped)
    try await eventually { [copied] in copied.value.count == 2 }
    #expect(copied.value.first?.text.contains("{{prod-db}}") == true)
    #expect(copied.value.first?.concealed == false)
    #expect(copied.value.last?.text.hasPrefix("claude mcp remove --scope user vortex >/dev/null 2>&1; ") == true)
    #expect(copied.value.last?.text.contains("claude mcp add --transport http --scope user vortex http://127.0.0.1:47823/mcp") == true)
    #expect(copied.value.last?.concealed == true)
    await store.send(.stop)
  }
}
