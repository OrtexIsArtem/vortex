import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureSecrets

/// The onboarding's Claude Code step (S27, S28, S78): Connect through a fake command client.
@MainActor
struct ClaudeCodeStepTests {
  static let token = "tok3n-0123456789abcdef"
  let runs = LockIsolated<[(command: String, environment: [String: String], timeout: Duration)]>([])
  let opened = LockIsolated<[URL]>([])

  /// The server listens and the token is ready; `answers` answer the runs in order.
  func makeStore(_ answers: [CommandClient.Output], server: SecretsFeature.ServerStatus = .listening(port: 47823)) -> TestStoreOf<SecretsFeature> {
    var state = SecretsFeature.State()
    state.server = server
    state.token = Self.token
    let answers = LockIsolated(answers)
    let store = TestStore(initialState: state) {
      SecretsFeature()
    } withDependencies: {
      $0.commandClient.run = { [runs] command, _, environment, timeout in
        runs.withValue { $0.append((command, environment, timeout)) }
        return answers.withValue { $0.isEmpty ? CommandClient.Output(exitCode: 0) : $0.removeFirst() }
      }
      $0.fileClient.open = { [opened] url in opened.withValue { $0.append(url) } }
    }
    store.exhaustivity = .off
    return store
  }

  /// The check found `claude` at `path`: it prints the path, as `findClaudeCommand` does.
  static func found(_ path: String) -> CommandClient.Output {
    CommandClient.Output(exitCode: 0, stdout: Data("\(path)\n".utf8))
  }

  /// `claude` that only .zshrc puts on the PATH, or reaches through an alias, is found at the places its installers
  /// use, and run by its path (R4).
  @Test
  func claudeOutsideTheShellsPathIsFoundWhereItsInstallersPutIt() async {
    let check = SecretsFeature.findClaudeCommand
    #expect(check.hasPrefix("command -v claude 2>/dev/null || "))
    for place in ["$HOME/.local/bin/claude", "$HOME/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"] {
      #expect(check.contains("\"\(place)\""))
    }
    let store = makeStore([Self.found("/Users/me/My Apps/.claude/local/claude"), CommandClient.Output(exitCode: 0)])
    await store.send(.connectTapped)
    await store.receive(\.connectFinished) { $0.connect = .added }
    #expect(runs.value.count == 2)
    // Quoted as one word, spaces and all; non-interactive, as every CommandClient run (`shell -c`): no history.
    #expect(runs.value[1].command.hasPrefix("'/Users/me/My Apps/.claude/local/claude' mcp remove --scope user vortex"))
    #expect(runs.value[1].command.contains("'/Users/me/My Apps/.claude/local/claude' mcp add"))
    #expect(runs.value[1].environment == [SecretsFeature.tokenVariable: Self.token])
    #expect(!runs.value[1].command.contains(Self.token))
  }

  /// A check that finds nothing, or prints nothing, means Claude Code isn't installed.
  @Test
  func aCheckThatPrintsNoPathIsNotInstalled() async {
    let store = makeStore([CommandClient.Output(exitCode: 0)])
    await store.send(.connectTapped)
    await store.receive(\.connectFinished) { $0.connect = .notInstalled }
    #expect(runs.value.count == 1)
  }

  @Test
  func shellQuotingKeepsAPathOneWord() {
    #expect(SecretsFeature.shellQuoted("/a b/claude") == "'/a b/claude'")
    #expect(SecretsFeature.shellQuoted("/it's/claude") == "'/it'\\''s/claude'")
  }

  var isStepDone: Bool {
    @Shared(.onboardingStepsDone) var done
    return done.contains(SecretsFeature.id)
  }

  @Test
  func connectChecksForClaudeThenAddsVortexWithTheTokenOnlyInTheEnvironment() async {
    let store = makeStore([Self.found("/opt/homebrew/bin/claude"), CommandClient.Output(exitCode: 0)])
    await store.send(.connectTapped) { $0.connect = .running }
    await store.receive(\.connectFinished) { $0.connect = .added }
    #expect(runs.value.count == 2)
    #expect(runs.value[0].command == SecretsFeature.findClaudeCommand)
    #expect(runs.value[1].command.contains("'/opt/homebrew/bin/claude' mcp add --transport http --scope user vortex http://127.0.0.1:47823/mcp"))
    // The token is in the environment only: never in the command, which logs and QA show.
    #expect(runs.value.allSatisfy { !$0.command.contains(Self.token) })
    #expect(runs.value[1].environment == [SecretsFeature.tokenVariable: Self.token])
    // At most 30 s in all (S78).
    #expect(runs.value.map(\.timeout).reduce(.zero, +) <= .seconds(30))
    #expect(store.state.settings.addedToClaudeCode)
    #expect(isStepDone)
  }

  @Test
  func withoutClaudeItSaysClaudeCodeIsNotInstalledAndRunsNothingElse() async {
    let store = makeStore([CommandClient.Output(exitCode: 1)])
    await store.send(.connectTapped)
    await store.receive(\.connectFinished) { $0.connect = .notInstalled }
    #expect(runs.value.count == 1)
    #expect(!isStepDone)
    #expect(!store.state.settings.addedToClaudeCode)
    await store.send(.getClaudeCodeTapped).finish()
    #expect(opened.value == [SecretsFeature.claudeCodeURL])
  }

  /// A failure keeps only the exit code: what the shell printed, the token included, never shows.
  @Test
  func aFailureKeepsOnlyTheExitCodeNeverTheOutput() async {
    let leaked = CommandClient.Output(exitCode: 1, stdout: Data("Bearer \(Self.token)".utf8), stderr: Data("bad \(Self.token)".utf8))
    let store = makeStore([Self.found("/opt/homebrew/bin/claude"), leaked])
    await store.send(.connectTapped)
    await store.receive(\.connectFinished) { $0.connect = .failed(exitCode: 1) }
    #expect(!String(describing: store.state.connect).contains(Self.token))
    #expect(!isStepDone)
  }

  /// The 30 s limit ends as any other failure (S78).
  @Test
  func reachingTheTimeLimitIsAFailure() async {
    let store = makeStore([Self.found("/opt/homebrew/bin/claude"), CommandClient.Output(exitCode: 143, timedOut: true)])
    await store.send(.connectTapped)
    await store.receive(\.connectFinished) { $0.connect = .failed(exitCode: 143) }
    #expect(runs.value.last?.timeout == SecretsFeature.connectTime)
    #expect(!isStepDone)
  }

  @Test
  func connectWaitsForTheServerToListen() async {
    for server in [SecretsFeature.ServerStatus.starting, .off, .failed("port taken")] {
      let store = makeStore([], server: server)
      #expect(!store.state.canConnect)
      await store.send(.connectTapped).finish()
    }
    #expect(runs.value.isEmpty)
  }

  /// Done also when Claude Code connected before, or connects now (S27).
  @Test
  func theStepIsDoneOnceClaudeCodeConnects() async {
    let store = makeStore([])
    #expect(!isStepDone)
    await store.send(.server(.sessionStarted(MCPSession(id: "s1", client: "Claude Code"))))
    #expect(isStepDone)
  }
}

extension SecretsFeatureTests {
  /// Done at start when Claude Code connected in an earlier launch (S27, S78).
  @Test
  func theClaudeCodeStepIsDoneAtStartAfterAnEarlierConnection() async {
    @Shared(.secretsSettings) var settings
    $settings.withLock { $0.hasConnected = true }
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    @Shared(.onboardingStepsDone) var done
    #expect(done.contains(SecretsFeature.id))
    await store.send(.stop)
  }
}
