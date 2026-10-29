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
  let bodies = LockIsolated<[String]>([])
  let removedNotifications = LockIsolated<[String]>([])
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
      $0.commandClient.run = { [ran] command, folder, environment, _ in
        ran.withValue { $0.append((command, environment, folder?.path)) }
        // Prints the value, as a careless command might.
        return CommandClient.Output(exitCode: 0, stdout: Data("connected with \(environment["VORTEX_KEY_1"] ?? "")\n".utf8))
      }
      $0.mcpServer.serve = { [events] _, _ in events.stream }
      $0.mcpServer.reply = { [replies] _, result in replies.withValue { $0.append(result) } }
      $0.notificationClient.requestAuthorization = {
        Issue.record("A request never asks whether Vortex may notify (S25)")
        return false
      }
      $0.notificationClient.post = { [posted, bodies] id, title, body, _ in
        posted.withValue { $0.append("\(id): \(title)") }
        bodies.withValue { $0.append(body) }
      }
      $0.notificationClient.remove = { [removedNotifications] id in removedNotifications.withValue { $0.append(id) } }
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
  func theLastDeletedKeysValueGoesAtTheNextStart() async {
    // Vortex quit while the deletion could still be taken back: no key is left, only its value.
    let account = "\(SecretsFeature.keychainService)/DELETED"
    keychain.withValue { $0[account] = value }
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    #expect(keychain.value[account] == nil)
    await store.send(.stop)
  }

  @Test
  func aDatabaseOnlyInMemoryRemovesNoValue() async {
    // Its file didn't open: the keychain then holds the only copy of every value.
    let account = "\(SecretsFeature.keychainService)/UNREAD"
    keychain.withValue { $0[account] = value }
    let store = makeStore()
    store.dependencies.databaseIsOnDisk = false
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
    try await eventually { [posted] in posted.value == ["\(SecretsFeature.notificationID(approval.id)): Claude Code → prod-db"] }

    await store.send(.approveTapped(approval.id))
    await store.receive(\.commandEnded)
    try await eventually { [replies] in replies.value.count == 1 }
    #expect(ran.value.first?.command == #"psql "${VORTEX_KEY_1}" -c 'select 1'"#)
    #expect(ran.value.first?.environment == ["VORTEX_KEY_1": value])
    #expect(ran.value.first?.folder == "/tmp")
    #expect(replies.value.first == MCPToolResult(text: "exit code 0\nconnected with {{prod-db}}\n", isError: false))
    #expect(store.state.indicators[SecretsFeature.id] == nil)
    #expect(store.state.keys.first?.lastUsedAt == now.value)
    try await eventually { [database] in try await database.read { db in try SecretKey.fetchAllReadable(db) }.first?.lastUsedAt != nil }

    // The same session runs it again without asking.
    events.continuation.yield(.call(call(.run, ["command": "echo {{PROD-DB}}"], id: 2)))
    await store.receive(\.server.call)
    await store.receive(\.commandEnded)
    try await eventually { [replies] in replies.value.count == 2 }
    #expect(store.state.approvals.isEmpty)
    #expect(ran.value.count == 2)
    await store.send(.stop)
  }

  @Test
  func aDeniedOrUnansweredRequestGetsAnError() async throws {
    let store = makeStore()
    await start(store)
    await addKey(store)
    events.continuation.yield(.call(call(.run, ["command": "psql \"{{prod-db}}\""], id: 1)))
    await store.receive(\.server.call)
    await store.send(.denyTapped(try #require(store.state.approvals.first?.id)))
    try await eventually { [replies] in replies.value.count == 1 }
    #expect(replies.value.first?.isError == true)
    #expect(replies.value.first?.text.contains("did not allow {{prod-db}}") == true)

    events.continuation.yield(.call(call(.run, ["command": "psql \"{{prod-db}}\""], id: 2)))
    await store.receive(\.server.call)
    await clock.advance(by: SecretsFeature.answerTime)
    await store.receive(\.approvalUnanswered)
    #expect(store.state.approvals.isEmpty)
    try await eventually { [replies] in replies.value.last?.text.contains("Nobody allowed {{prod-db}} in time") == true }
    #expect(ran.value.isEmpty)
    await store.send(.stop)
  }

  @Test
  func eachRequestHasANotificationOfItsOwnAndOneGivenUpGoes() async throws {
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
    let (waiting, givenUp) = (store.state.approvals[0].id, store.state.approvals[1].id)
    try await eventually { [posted] in
      Set(posted.value) == [
        "\(SecretsFeature.notificationID(waiting)): Claude Code → prod-db",
        "\(SecretsFeature.notificationID(givenUp)): Claude Code → github",
      ]
    }
    events.continuation.yield(.cancelled(second.id))
    await store.receive(\.server.cancelled)
    #expect(store.state.approvals.map(\.names) == [["prod-db"]])
    try await eventually { [replies] in replies.value.contains(MCPToolResult(text: "Cancelled.", isError: true)) }
    try await eventually { [removedNotifications] in removedNotifications.value.last == SecretsFeature.notificationID(givenUp) }
    #expect(store.state.indicators[SecretsFeature.id]?.trailing == [.text("prod-db")])
    await store.send(.stop)
  }

  @Test
  func aPressAnswersTheRequestItsNotificationShowsWhateverCameSince() async throws {
    let store = makeStore()
    await start(store)
    await addKey(store)
    await addKey(store, name: "github")
    events.continuation.yield(.call(call(.run, ["command": "psql \"{{prod-db}}\""], id: 1)))
    await store.receive(\.server.call)
    let shown = try #require(store.state.approvals.first?.id)
    // Another request comes in while the first one's notification is on screen.
    events.continuation.yield(.call(call(.run, ["command": "gh api -X DELETE repos/x/y -H \"Authorization: Bearer {{github}}\""], id: 2)))
    await store.receive(\.server.call)
    await store.send(.notificationButtonPressed(NotificationClient.Press(notification: SecretsFeature.notificationID(shown), button: SecretsFeature.allowButtonID)))
    await store.receive(\.approveTapped)
    try await eventually { [ran] in ran.value.count == 1 }
    #expect(ran.value.first?.command == #"psql "${VORTEX_KEY_1}""#)
    #expect(store.state.approvals.map(\.names) == [["github"]])
    // A notification left from a run before answers nothing.
    await store.send(.notificationButtonPressed(NotificationClient.Press(notification: "secrets.approval", button: SecretsFeature.allowButtonID)))
    #expect(store.state.approvals.map(\.names) == [["github"]])
    await store.send(.stop)
  }

  @Test
  func whatClaudeGivesUpIsAnsweredCancelledAndStops() async throws {
    let store = makeStore()
    store.dependencies.commandClient.run = { [clock] _, _, _, _ in
      try await clock.sleep(for: .seconds(30))
      return CommandClient.Output(exitCode: 0)
    }
    await start(store)
    await addKey(store)
    // Waiting for «Дозволити»: it never ran.
    let waiting = call(.run, ["command": "psql \"{{prod-db}}\""], id: 1)
    events.continuation.yield(.call(waiting))
    await store.receive(\.server.call)
    events.continuation.yield(.cancelled(waiting.id))
    await store.receive(\.server.cancelled)
    #expect(store.state.approvals.isEmpty)
    #expect(store.state.keys.first?.lastUsedAt == nil)

    // Running: it is stopped, and as the key was handed to it, it counts as used.
    let running = call(.run, ["command": "psql \"{{prod-db}}\" -c 'delete from bookings'"], id: 2)
    events.continuation.yield(.call(running))
    await store.receive(\.server.call)
    await store.send(.approveTapped(try #require(store.state.approvals.first?.id)))
    #expect(store.state.running[running.id] != nil)
    events.continuation.yield(.cancelled(running.id))
    await store.receive(\.server.cancelled)
    #expect(store.state.running.isEmpty)
    #expect(store.state.keys.first?.lastUsedAt == now.value)
    try await eventually { [replies] in replies.value.filter { $0 == MCPToolResult(text: "Cancelled.", isError: true) }.count == 2 }
    // Stopped: the command's own answer never comes.
    await clock.advance(by: .seconds(30))
    #expect(replies.value.count == 2)
    await store.send(.stop)
  }

  @Test
  func turningKeysOffStopsACommandStillRunning() async throws {
    let store = makeStore()
    store.dependencies.commandClient.run = { [clock] _, _, _, _ in
      try await clock.sleep(for: .seconds(30))
      return CommandClient.Output(exitCode: 0)
    }
    await start(store)
    await addKey(store)
    let running = call(.run, ["command": "psql \"{{prod-db}}\" -c 'delete from bookings'"], id: 1)
    events.continuation.yield(.call(running))
    await store.receive(\.server.call)
    await store.send(.approveTapped(try #require(store.state.approvals.first?.id)))
    await store.send(.stop)
    #expect(store.state.running.isEmpty)
    try await eventually { [replies] in replies.value == [MCPToolResult(text: "Cancelled.", isError: true)] }
    await clock.advance(by: .seconds(30))
    #expect(replies.value.count == 1)
  }

  @Test
  func aKeyCountsAsUsedOnlyOnceACommandRanWithIt() async throws {
    let store = makeStore()
    await start(store)
    await addKey(store)
    let key = try #require(store.state.keys.first)
    // Its value is gone from the keychain: nothing runs.
    keychain.withValue { $0["\(SecretsFeature.keychainService)/\(key.id.uuidString)"] = nil }
    events.continuation.yield(.call(call(.run, ["command": "psql \"{{prod-db}}\""], id: 1)))
    await store.receive(\.server.call)
    await store.send(.approveTapped(try #require(store.state.approvals.first?.id)))
    await store.receive(\.commandEnded)
    #expect(store.state.keys.first?.lastUsedAt == nil)
    #expect(store.state.running.isEmpty)
    await store.send(.stop)
  }

  @Test
  func aValueShownGoesOutOfSightWhenTheWindowCloses() async throws {
    let store = makeStore()
    await start(store)
    await addKey(store)
    await store.send(.revealTapped(try #require(store.state.keys.first?.id)))
    await store.receive(\.revealed)
    await store.send(.addTapped)
    await store.send(.draftChanged(KeyDraft(value: "s3cret", showsValue: true)))
    await store.send(.windowClosed)
    #expect(store.state.revealed == nil)
    #expect(store.state.draft?.showsValue == false)
    #expect(store.state.draft?.value == "s3cret")
    await store.send(.stop)
  }

  @Test
  func theLogOfUsesFromBeforeIsGone() async throws {
    // A database from before keeps no log: Claude Code shows every command in its own history.
    try SecretKey.migrator.migrate(database, upTo: "secrets.v1")
    #expect(try await database.read { db in try db.tableExists("secrets_use") })
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    #expect(try await database.read { db in try db.tableExists("secrets_use") } == false)
    await store.send(.stop)
  }

  @Test
  func theNotificationShowsTheStartOfTheCommandAndGoesOnceAnswered() async throws {
    let store = makeStore()
    await start(store)
    // Notifications of a run before go as the feature starts.
    try await eventually { [removedNotifications] in removedNotifications.value == [SecretsFeature.approvalNotificationPrefix] }
    await addKey(store)
    let command = "psql \"{{prod-db}}\" -c \"" + String(repeating: "select 1; ", count: 40) + "\""
    events.continuation.yield(.call(call(.run, ["command": .string(command)], id: 1)))
    await store.receive(\.server.call)
    try await eventually { [bodies] in bodies.value.count == 1 }
    #expect(bodies.value.first?.count == 240)
    #expect(bodies.value.first?.hasSuffix("…") == true)
    let id = try #require(store.state.approvals.first?.id)
    await store.send(.denyTapped(id))
    try await eventually { [removedNotifications] in removedNotifications.value.last == SecretsFeature.notificationID(id) }
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
  func theEyeShowsTheValueWithoutAskingForAWhileAndItsCopyIsConcealed() async throws {
    let store = makeStore()
    await start(store)
    await addKey(store)
    let key = try #require(store.state.keys.first)
    await store.send(.revealTapped(key.id))
    await store.receive(\.revealed)
    #expect(store.state.revealed?.value == value)
    await store.send(.copyValueTapped)
    try await eventually { [copied] in copied.value.count == 1 }
    #expect(copied.value.first?.text == value)
    #expect(copied.value.first?.concealed == true)
    await clock.advance(by: SecretsFeature.revealTime)
    await store.receive(\.hideTapped)
    #expect(store.state.revealed == nil)
    await store.send(.stop)
  }

  @Test
  func copyingTheNameGivesWhatToSayToClaude() async throws {
    let store = makeStore()
    await start(store)
    await addKey(store)
    await store.send(.copyNameTapped(try #require(store.state.keys.first?.id)))
    try await eventually { [copied] in copied.value.count == 1 }
    #expect(copied.value.first?.text == "prod-db (Vortex)")
    #expect(copied.value.first?.concealed == false)
    await store.send(.stop)
  }

  @Test
  func theConnectCommandIsCopiedConcealed() async throws {
    let store = makeStore()
    await start(store)
    await store.send(.copyConnectCommandTapped)
    try await eventually { [copied] in copied.value.count == 1 }
    #expect(copied.value.last?.text.hasPrefix("claude mcp remove --scope user vortex >/dev/null 2>&1; ") == true)
    #expect(copied.value.last?.text.contains("claude mcp add --transport http --scope user vortex http://127.0.0.1:47823/mcp") == true)
    #expect(copied.value.last?.concealed == true)
    await store.send(.stop)
  }
}

/// The Notifications row in Keys' settings (S22.3, S40, S47).
@MainActor
struct SecretsPermissionTests {
  @Test
  func theSettingsRowOpensThePageRestartsAndReadsAgain() async {
    let pages = LockIsolated<[Permission]>([])
    let refreshes = LockIsolated(0)
    let relaunches = LockIsolated(0)
    let store = TestStore(initialState: SecretsFeature.State()) {
      SecretsFeature()
    } withDependencies: {
      $0.permissionPage.open = { [pages] permission in pages.withValue { $0.append(permission) } }
      $0.permissionsClient.refresh = { [refreshes] in refreshes.withValue { $0 += 1 } }
      $0.systemClient.relaunch = { [relaunches] in relaunches.withValue { $0 += 1 } }
    }
    store.exhaustivity = .off
    await store.send(.settingsShown).finish()
    #expect(refreshes.value == 1)
    await store.send(.turnOnTapped(.notifications)).finish()
    #expect(pages.value == [.notifications])
    await store.send(.restartTapped).finish()
    #expect(relaunches.value == 1)
  }
}
