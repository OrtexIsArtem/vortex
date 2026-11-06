import Foundation
import Testing

@testable import VortexPlatform

/// Runs real commands in the user's shell, as the app does. A busy machine running the whole suite can hold up any
/// await here for many seconds, so no test bounds how long a call takes by less than a minute.
struct CommandClientTests {
  let client = CommandClient.liveValue

  func text(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self)
  }

  @Test
  func theOutputsTheExitCodeAndTheVariablesComeBack() async throws {
    let output = try await client.run(
      #"printf %s "$VORTEX_TEST"; echo oops >&2; exit 3"#,
      nil,
      ["VORTEX_TEST": "s3cret value"],
      .seconds(20)
    )
    #expect(text(output.stdout).hasSuffix("s3cret value"))
    #expect(text(output.stderr).contains("oops"))
    #expect(output.exitCode == 3)
    #expect(!output.timedOut)
  }

  @Test
  func itRunsInTheFolderGiven() async throws {
    let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
    let output = try await client.run("pwd -P", folder, [:], .seconds(20))
    #expect(text(output.stdout).trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(folder.path))
  }

  @Test
  func itIsStoppedWhenItsTimeIsUp() async throws {
    // Left alone, it would end by itself a minute later, with exit code 0.
    let output = try await client.run("sleep 60", nil, [:], .milliseconds(500))
    #expect(output.timedOut)
    #expect(output.exitCode == 128 + SIGTERM)
  }

  @Test
  func whatItLeavesRunningDoesNotKeepItWaiting() async throws {
    // `sleep` keeps the output open past the time limit, so waiting for it would end in a time-out.
    let output = try await client.run("sleep 120 & echo done", nil, [:], .seconds(60))
    #expect(text(output.stdout).contains("done"))
    #expect(output.exitCode == 0)
    #expect(!output.timedOut)
  }

  /// A home folder with these startup files, for the shell to read instead of the user's.
  func home(_ files: [String: String]) throws -> URL {
    let home = FileManager.default.temporaryDirectory.appending(path: "vortex-home-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    for (name, text) in files {
      try text.write(to: home.appending(path: name), atomically: true, encoding: .utf8)
    }
    return home
  }

  @Test
  func theTerminalsEnvironmentHasWhatZshrcAdds() async throws {
    let home = try home([
      ".zprofile": "export FROM_ZPROFILE=yes\n",
      // Emacs's guard, common in .zshrc: it would stop here for a dumb terminal.
      ".zshrc": "[[ $TERM == dumb ]] && return\necho 'Welcome back'\nexport PATH=\"/opt/vortex-test/bin:$PATH\"\nexport FROM_ZSHRC=yes\n",
    ])
    defer { try? FileManager.default.removeItem(at: home) }
    let base = ["HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TERM": "dumb"]
    let environment = try #require(await TerminalEnvironment.ask(shell: "/bin/zsh", base: base))
    #expect(environment["PATH"]?.hasPrefix("/opt/vortex-test/bin:") == true)
    #expect(environment["FROM_ZSHRC"] == "yes")
    #expect(environment["FROM_ZPROFILE"] == "yes")
    #expect(environment["TERM"] == "dumb")
    #expect(environment["PWD"] == nil)
  }

  @Test
  func aShellThatDoesNotAnswerInTimeGivesNoEnvironment() async throws {
    // Left alone, it would answer a minute later.
    let home = try home([".zshrc": "sleep 60\n"])
    defer { try? FileManager.default.removeItem(at: home) }
    let base = ["HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TERM": "dumb"]
    let start = ContinuousClock.now
    #expect(await TerminalEnvironment.ask(shell: "/bin/zsh", base: base, timeout: .milliseconds(500)) == nil)
    // Given up when its time was up, not once the shell answered.
    #expect(ContinuousClock.now - start < .seconds(60))
  }

  @Test
  func whatTheStartupFilesLeaveRunningDoesNotHoldItUp() async throws {
    // A process of another session keeps whatever it was given, which killing the shell's group doesn't reach. It
    // outlives the shell's time limit, so waiting for it would give no environment.
    let home = try home([
      // The shell goes on only once it has left the group; still in it, it would be killed with the shell.
      ".zshrc": "/usr/bin/perl -e 'use POSIX; setsid(); open my $f, \">$ENV{HOME}/detached\"; sleep 30' &\n"
        + "until [[ -e $HOME/detached ]]; do sleep 0.01; done\nexport FROM_ZSHRC=yes\n",
    ])
    defer { try? FileManager.default.removeItem(at: home) }
    let base = ["HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TERM": "dumb"]
    let environment = await TerminalEnvironment.ask(shell: "/bin/zsh", base: base)
    #expect(environment?["FROM_ZSHRC"] == "yes")
  }

  @Test
  func editingAStartupFileThroughALinkOrRemovingOneChangesTheStamp() throws {
    let home = try home([".zprofile": "export A=1\n"])
    defer { try? FileManager.default.removeItem(at: home) }
    // A dotfile manager keeps the real file elsewhere and links it in.
    let dotfiles = home.appending(path: "dotfiles/zshrc")
    try FileManager.default.createDirectory(at: dotfiles.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "export B=1\n".write(to: dotfiles, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: home.appending(path: ".zshrc"), withDestinationURL: dotfiles)
    let past = Date(timeIntervalSinceNow: -3600)
    for url in [dotfiles, home.appending(path: ".zprofile")] {
      try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: url.path)
    }
    let first = TerminalEnvironment.stamp(home: home, zdotdir: nil)

    try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: dotfiles.path)
    let edited = TerminalEnvironment.stamp(home: home, zdotdir: nil)
    #expect(edited != first)

    try FileManager.default.removeItem(at: home.appending(path: ".zprofile"))
    #expect(TerminalEnvironment.stamp(home: home, zdotdir: nil) != edited)
  }

  @Test
  func aCommandNotFoundIsTheShellsCode127() {
    #expect(CommandClient.Output(exitCode: 127).isCommandNotFound)
    #expect(!CommandClient.Output(exitCode: 127, timedOut: true).isCommandNotFound)
    #expect(!CommandClient.Output(exitCode: 1).isCommandNotFound)
  }

  @Test
  func itGetsNoInputAndNoneOfVortexsEnvironment() async throws {
    setenv("VORTEX_LEAK_CHECK", "leaked", 1)
    defer { unsetenv("VORTEX_LEAK_CHECK") }
    let output = try await client.run(#"cat; printf '[%s]' "$VORTEX_LEAK_CHECK""#, nil, [:], .seconds(20))
    #expect(text(output.stdout).hasSuffix("[]"))
  }
}

/// QA mode's stand-in: nothing runs, a script answers.
struct QACommandClientTests {
  let rules: [QASimulation.CommandRule] = [
    .init(match: "command -v claude", exitCode: 127, stderr: "not found"),
    .init(match: "claude mcp add", exitCode: 0, stdout: "added", echo: true),
  ]

  @Test
  func nothingRunsWithoutAScript() async throws {
    let client = CommandClient.qa(scripts: { [] })
    let marker = FileManager.default.temporaryDirectory.appending(path: "vortex-qa-never-\(UUID().uuidString)")
    let output = try await client.run("touch '\(marker.path)'", nil, [:], .seconds(5))
    #expect(output == CommandClient.Output(exitCode: 0))
    #expect(!FileManager.default.fileExists(atPath: marker.path))
  }

  @Test
  func theFirstMatchingScriptAnswers() async throws {
    let client = CommandClient.qa(scripts: { rules })
    let missing = try await client.run("command -v claude", nil, ["TOKEN": "x"], .seconds(5))
    #expect(missing.isCommandNotFound)
    #expect(String(decoding: missing.stderr, as: UTF8.self) == "not found")
    let added = try await client.run("claude mcp add vortex", nil, [:], .seconds(5))
    #expect(String(decoding: added.stdout, as: UTF8.self) == "claude mcp add vortex\nadded")
  }

  @Test
  func aScriptThatReachesTheTimeLimitTimesOutAsTheLiveClientDoes() async throws {
    let client = CommandClient.qa(scripts: { [.init(match: "claude", exitCode: 0, stdout: "added", delay: 40)] })
    let output = try await client.run("claude mcp add vortex", nil, [:], .milliseconds(50))
    #expect(output.timedOut)
    #expect(output.exitCode == 143)
    let quick = try await CommandClient.qa(scripts: { [.init(match: "claude", exitCode: 0, delay: 0.01)] })
      .run("claude mcp add vortex", nil, [:], .seconds(5))
    #expect(!quick.timedOut)
    #expect(quick.exitCode == 0)
  }

  @Test
  func theLogNamesTheVariablesNeverTheirValues() async throws {
    let client = CommandClient.qa(scripts: { [] })
    _ = try await client.run("echo qa-log-check", nil, ["TOKEN": "value-never-logged"], .seconds(5))
    let entry = QALog.events.value.last { $0.detail["command"] == "echo qa-log-check" }
    #expect(entry?.detail["environment"] == "TOKEN")
    #expect(entry.map { !$0.detail.values.contains { $0.contains("value-never-logged") } } == true)
  }
}
