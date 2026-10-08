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

  @Test
  func itGetsNoInputAndNoneOfVortexsEnvironment() async throws {
    setenv("VORTEX_LEAK_CHECK", "leaked", 1)
    defer { unsetenv("VORTEX_LEAK_CHECK") }
    let output = try await client.run(#"cat; printf '[%s]' "$VORTEX_LEAK_CHECK""#, nil, [:], .seconds(20))
    #expect(text(output.stdout).hasSuffix("[]"))
  }
}
