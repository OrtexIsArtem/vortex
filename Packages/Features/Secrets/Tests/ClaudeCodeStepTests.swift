import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureSecrets

/// The onboarding's Claude Code step: Connect through a fake command client.
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
      $0.fileClient.info = { [files] url in files.value[url.path] }
      $0.continuousClock = clock
    }
    store.exhaustivity = .off
    return store
  }

  let clock = TestClock()
  /// The files the fake disk holds, by path.
  let files = LockIsolated<[String: FileInfo]>([:])

  /// An executable `claude` at `path`.
  func installClaude(at path: String) {
    files.withValue { $0[path] = FileInfo(size: 1, isDirectory: false, isExecutable: true) }
  }

  /// What `pathCommand` prints in the user's shell: whatever a startup file printed first, then the marked PATH.
  static func shellPATH(_ path: String, printedBefore: String = "") -> CommandClient.Output {
    let marker = SecretsFeature.pathMarker
    return CommandClient.Output(exitCode: 0, stdout: Data("\(printedBefore)\(marker)\n\(path)\n\(marker)\n".utf8))
  }

  /// "Connect again" runs as Connect does, with the spinner and the result shown under it; after a relaunch the step
  /// still reads as added.
  @Test
  func connectAgainShowsItsRunAndARelaunchKeepsTheSuccess() async {
    let store = makeStore([CommandClient.Output(exitCode: 1)])
    #expect(!store.state.showsConnectAgain)
    await store.send(.server(.sessionStarted(MCPSession(id: "s1", client: "Claude Code"))))
    #expect(store.state.showsConnectAgain)
    await store.send(.connectTapped) { $0.connect = .running }
    await store.receive(\.connectFinished) { $0.connect = .notInstalled }

    // Relaunched after a success: the run's state is gone, the saved success isn't.
    var relaunched = SecretsFeature.State()
    relaunched.$settings.withLock { $0.addedToClaudeCode = true }
    #expect(relaunched.connect == .idle)
    #expect(relaunched.showsConnectAgain)
  }

  /// 30 s on the clock end the step, however long the runs' own limits are: the shell's first start counts too.
  @Test
  func thirtySecondsOnTheClockEndConnectAsAFailureAndStopTheRun() async {
    let stopped = LockIsolated(false)
    let store = makeStore([])
    store.dependencies.commandClient.run = { [stopped] _, _, _, _ in
      // A shell that never answers: only cancelling stops it, as CommandClient then stops what it started.
      do {
        try await Task.sleep(for: .seconds(3600))
      } catch {
        stopped.setValue(true)
        throw error
      }
      return CommandClient.Output(exitCode: 0)
    }
    await store.send(.connectTapped) { $0.connect = .running }
    await clock.advance(by: .seconds(29))
    #expect(store.state.connect == .running)
    await clock.advance(by: .seconds(1))
    await store.receive(\.connectTimeLimitReached) { $0.connect = .failed(exitCode: 143) }
    for _ in 0..<100 where !stopped.value {
      try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(stopped.value)
    #expect(!store.state.settings.addedToClaudeCode)
  }

  /// A run that ends in time stops the limit: nothing changes 30 s later.
  @Test
  func aConnectThatEndsInTimeIsNotFailedLater() async {
    installClaude(at: "/opt/homebrew/bin/claude")
    let store = makeStore([Self.shellPATH("/usr/bin:/bin:/opt/homebrew/bin"), CommandClient.Output(exitCode: 0)])
    await store.send(.connectTapped)
    await store.receive(\.connectFinished) { $0.connect = .added }
    await clock.advance(by: .seconds(31))
    #expect(store.state.connect == .added)
  }

  /// The check asks the shell only for its PATH, in plain commands zsh, bash and fish all run.
  @Test
  func theCheckIsPlainCommandsEveryShellRuns() {
    let check = SecretsFeature.pathCommand
    #expect(check == "echo __vortex_claude_path__; printenv PATH; echo __vortex_claude_path__")
    // No sh-only syntax: fish has no do/done, then/fi, { …; } or ||.
    for syntax in ["do ", "done", "then", "fi", "{", "||", "&&", "$("] {
      #expect(!check.contains(syntax))
    }
  }

  /// What zsh, bash and fish print for the check reads the same; what a startup file prints first is never read, and
  /// without both markers there is no PATH.
  @Test
  func theMarkedPathIsReadFromEveryShellsOutput() {
    let marker = SecretsFeature.pathMarker
    let path = "/Users/me/.local/bin:/opt/homebrew/bin:/usr/bin:/bin"
    // zsh and bash: `echo` and `printenv` print lines; fish prints the PATH list joined by colons for `printenv` too.
    #expect(SecretsFeature.markedPath("\(marker)\n\(path)\n\(marker)\n") == path)
    // A greeting from .zshenv or config.fish, and a CRLF line end.
    #expect(SecretsFeature.markedPath("Welcome back\nalias claude=/x/claude\n\(marker)\r\n\(path)\r\n\(marker)\r\n") == path)
    // An unset PATH: `printenv` prints nothing.
    #expect(SecretsFeature.markedPath("\(marker)\n\(marker)\n") == "")
    // Not ours: one marker, none, or more than a line between them.
    #expect(SecretsFeature.markedPath("\(marker)\n\(path)\n") == nil)
    #expect(SecretsFeature.markedPath("/opt/homebrew/bin/claude\n") == nil)
    #expect(SecretsFeature.markedPath("\(marker)\n/a\n/b\n\(marker)\n") == nil)
    #expect(SecretsFeature.markedPath("x\(marker)\n\(path)\n\(marker)\n") == nil)
  }

  /// Only absolute PATH entries count, then the installers' places; each candidate is an absolute path named `claude`.
  @Test
  func candidatesAreAbsolutePathsNamedClaude() {
    let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
    let candidates = SecretsFeature.claudeCandidates(path: "/usr/bin:.:bin:~/bin::/opt/homebrew/bin/:/usr/bin", home: home)
    #expect(candidates.map(\.path) == [
      "/usr/bin/claude", "/opt/homebrew/bin/claude", "/Users/me/.local/bin/claude", "/Users/me/.claude/local/claude",
      "/usr/local/bin/claude",
    ])
    #expect(candidates.allSatisfy { $0.path.hasPrefix("/") && $0.lastPathComponent == "claude" })
  }

  /// A greeting before the PATH changes nothing: Vortex runs the executable it found on the PATH, by its absolute
  /// path, never a line of output.
  @Test
  func noiseBeforeThePathIsNeverRun() async {
    installClaude(at: "/opt/homebrew/bin/claude")
    let check = Self.shellPATH("/usr/bin:/opt/homebrew/bin", printedBefore: "Welcome back\nalias claude=/tmp/evil\n/tmp/evil\n")
    let store = makeStore([check, CommandClient.Output(exitCode: 0)])
    await store.send(.connectTapped)
    await store.receive(\.connectFinished) { $0.connect = .added }
    #expect(runs.value.count == 2)
    #expect(runs.value[1].command.hasPrefix("'/opt/homebrew/bin/claude' mcp remove --scope user vortex"))
    #expect(!runs.value[1].command.contains("evil"))
    #expect(!runs.value[1].command.contains("Welcome"))
  }

  /// A `claude` that isn't an executable file is skipped; with none left, Claude Code isn't installed and nothing runs.
  @Test
  func aClaudeThatIsNotAnExecutableFileIsNotInstalled() async {
    files.withValue {
      $0["/usr/bin/claude"] = FileInfo(size: 1, isDirectory: false, isExecutable: false)
      $0["/opt/homebrew/bin/claude"] = FileInfo(size: nil, isDirectory: true, isExecutable: false)
    }
    let store = makeStore([Self.shellPATH("/usr/bin:/opt/homebrew/bin")])
    await store.send(.connectTapped)
    await store.receive(\.connectFinished) { $0.connect = .notInstalled }
    #expect(runs.value.count == 1)
  }

  /// `claude` that only .zshrc puts on the PATH, or reaches by an alias, is found at the places its installers use,
  /// and run by its path, quoted as one word.
  @Test
  func claudeOutsideTheShellsPathIsFoundWhereItsInstallersPutIt() async {
    let local = URL.homeDirectory.appending(path: ".claude/local/claude").path
    installClaude(at: local)
    let store = makeStore([Self.shellPATH("/usr/bin:/bin"), CommandClient.Output(exitCode: 0)])
    await store.send(.connectTapped)
    await store.receive(\.connectFinished) { $0.connect = .added }
    #expect(runs.value.count == 2)
    #expect(runs.value[1].command.hasPrefix("\(SecretsFeature.shellQuoted(local)) mcp remove --scope user vortex"))
    #expect(runs.value[1].environment == [SecretsFeature.tokenVariable: Self.token])
    #expect(!runs.value[1].command.contains(Self.token))
  }

  /// A check that prints no marked PATH still looks at the installers' places; with nothing there, not installed.
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
    installClaude(at: "/opt/homebrew/bin/claude")
    let store = makeStore([Self.shellPATH("/usr/bin:/opt/homebrew/bin"), CommandClient.Output(exitCode: 0)])
    await store.send(.connectTapped) { $0.connect = .running }
    await store.receive(\.connectFinished) { $0.connect = .added }
    #expect(runs.value.count == 2)
    #expect(runs.value[0].command == SecretsFeature.pathCommand)
    #expect(runs.value[0].environment.isEmpty)
    #expect(runs.value[1].command.contains("'/opt/homebrew/bin/claude' mcp add --transport http --scope user vortex http://127.0.0.1:47823/mcp"))
    // The token is in the environment only: never in the command, which logs and QA show.
    #expect(runs.value.allSatisfy { !$0.command.contains(Self.token) })
    #expect(runs.value[1].environment == [SecretsFeature.tokenVariable: Self.token])
    // At most 30 s in all.
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
    installClaude(at: "/opt/homebrew/bin/claude")
    let store = makeStore([Self.shellPATH("/usr/bin:/opt/homebrew/bin"), leaked])
    await store.send(.connectTapped)
    await store.receive(\.connectFinished) { $0.connect = .failed(exitCode: 1) }
    #expect(!String(describing: store.state.connect).contains(Self.token))
    #expect(!isStepDone)
  }

  /// The 30 s limit ends as any other failure.
  @Test
  func reachingTheTimeLimitIsAFailure() async {
    installClaude(at: "/opt/homebrew/bin/claude")
    let store = makeStore([Self.shellPATH("/usr/bin:/opt/homebrew/bin"), CommandClient.Output(exitCode: 143, timedOut: true)])
    await store.send(.connectTapped)
    await store.receive(\.connectFinished) { $0.connect = .failed(exitCode: 143) }
    #expect(runs.value.last?.timeout == SecretsFeature.connectTime)
    #expect(!isStepDone)
  }

  /// With the server down, the step shows the Keys card's message, which names the port and says what to do, never
  /// Settings' raw status line; Connect is hidden and Skip stays.
  @Test
  func withTheServerDownTheStepShowsTheKeysCardsMessageWithThePort() {
    var state = SecretsFeature.State()
    state.$settings.withLock { $0.port = 55555 }
    state.token = Self.token
    state.server = .failed("Address already in use")
    let failure = SecretsFeature.ServerFailure(port: 55555, reason: "Address already in use")
    #expect(state.claudeStepBody == .serverFailure(failure))
    #expect(state.serverFailure == failure)
    #expect(!state.canConnect)
    #expect(!state.isClaudeStepDone)
    for server in [SecretsFeature.ServerStatus.off, .starting, .listening(port: 55555)] {
      state.server = server
      #expect(state.claudeStepBody == .connect)
      #expect(state.serverFailure == nil)
    }
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

  /// Done also when Claude Code connected before, or connects now.
  @Test
  func theStepIsDoneOnceClaudeCodeConnects() async {
    let store = makeStore([])
    #expect(!isStepDone)
    await store.send(.server(.sessionStarted(MCPSession(id: "s1", client: "Claude Code"))))
    #expect(isStepDone)
  }
}

extension SecretsFeatureTests {
  /// Done at start when Claude Code connected in an earlier launch.
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
