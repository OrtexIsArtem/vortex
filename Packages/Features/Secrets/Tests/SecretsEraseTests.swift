import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureSecrets

@MainActor
struct SecretsEraseTests {
  /// Erase Data takes every key's value and the MCP token out of the keychain, and Claude Code forgets Vortex's server.
  @Test
  func erasingKeysClearsTheKeychainAndTheClaudeEntry() async {
    let deleted = LockIsolated<[String]>([])
    let commands = LockIsolated<[String]>([])
    await withDependencies {
      $0.keychainClient.accounts = { service in service == SecretsFeature.keychainService ? ["a", "b"] : [] }
      $0.keychainClient.delete = { service, account in deleted.withValue { $0.append("\(service)/\(account)") } }
      $0.commandClient.run = { command, _, _, _ in
        commands.withValue { $0.append(command) }
        let marker = SecretsFeature.pathMarker
        return CommandClient.Output(exitCode: 0, stdout: Data("\(marker)\n/opt/tools\n\(marker)\n".utf8), stderr: Data(), timedOut: false)
      }
      $0.fileClient.info = { url in
        url.path == "/opt/tools/claude" ? FileInfo(size: 1, isDirectory: false, isExecutable: true) : nil
      }
    } operation: {
      await SecretsModule.eraseData()
    }
    #expect(deleted.value == [
      "\(SecretsFeature.keychainService)/a",
      "\(SecretsFeature.keychainService)/b",
      "\(SecretsFeature.serverService)/\(SecretsFeature.tokenAccount)",
    ])
    #expect(commands.value.count == 2)
    #expect(commands.value.last == "'/opt/tools/claude' mcp remove --scope user vortex")
  }

  /// Without Claude Code there is nothing to tell; the keychain is cleared all the same.
  @Test
  func erasingKeysWithoutClaudeCodeStillClearsTheKeychain() async {
    let deleted = LockIsolated<[String]>([])
    let commands = LockIsolated<[String]>([])
    await withDependencies {
      $0.keychainClient.accounts = { _ in ["a"] }
      $0.keychainClient.delete = { service, account in deleted.withValue { $0.append("\(service)/\(account)") } }
      $0.commandClient.run = { command, _, _, _ in
        commands.withValue { $0.append(command) }
        return CommandClient.Output(exitCode: 0, stdout: Data(), stderr: Data(), timedOut: false)
      }
      $0.fileClient.info = { _ in nil }
    } operation: {
      await SecretsModule.eraseData()
    }
    #expect(deleted.value.count == 2)
    #expect(commands.value == [SecretsFeature.pathCommand])
  }
}
