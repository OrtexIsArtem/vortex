import Foundation
import Testing

@testable import VortexPlatform

/// Runs real commands in the login shell, as the app does.
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
    let start = ContinuousClock.now
    let output = try await client.run("sleep 30", nil, [:], .milliseconds(500))
    #expect(output.timedOut)
    #expect(ContinuousClock.now - start < .seconds(10))
  }

  @Test
  func whatItLeavesRunningDoesNotKeepItWaiting() async throws {
    let start = ContinuousClock.now
    let output = try await client.run("sleep 30 & echo done", nil, [:], .seconds(20))
    #expect(text(output.stdout).contains("done"))
    #expect(output.exitCode == 0)
    #expect(ContinuousClock.now - start < .seconds(10))
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
    let home = try home([".zshrc": "sleep 30\n"])
    defer { try? FileManager.default.removeItem(at: home) }
    let base = ["HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TERM": "dumb"]
    let start = ContinuousClock.now
    #expect(await TerminalEnvironment.ask(shell: "/bin/zsh", base: base, timeout: .milliseconds(500)) == nil)
    #expect(ContinuousClock.now - start < .seconds(10))
  }

  @Test
  func whatTheStartupFilesLeaveRunningDoesNotHoldItUp() async throws {
    // A process of another session keeps whatever it was given, which killing the shell's group doesn't reach.
    let home = try home([".zshrc": "/usr/bin/perl -e 'use POSIX; setsid(); sleep 3' &\nexport FROM_ZSHRC=yes\n"])
    defer { try? FileManager.default.removeItem(at: home) }
    let base = ["HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TERM": "dumb"]
    let start = ContinuousClock.now
    let environment = await TerminalEnvironment.ask(shell: "/bin/zsh", base: base)
    #expect(environment?["FROM_ZSHRC"] == "yes")
    #expect(ContinuousClock.now - start < .seconds(2))
  }

  @Test
  func itGetsNoInputAndNoneOfVortexsEnvironment() async throws {
    setenv("VORTEX_LEAK_CHECK", "leaked", 1)
    defer { unsetenv("VORTEX_LEAK_CHECK") }
    let output = try await client.run(#"cat; printf '[%s]' "$VORTEX_LEAK_CHECK""#, nil, [:], .seconds(20))
    #expect(text(output.stdout).hasSuffix("[]"))
  }
}
