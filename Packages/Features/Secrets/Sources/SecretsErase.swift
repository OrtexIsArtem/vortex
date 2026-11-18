import ComposableArchitecture
import Foundation
import VortexPlatform

extension SecretsFeature {
  /// What Keys keeps outside the data folder, erased by Erase Data: every key's value and the MCP token in the
  /// keychain, and Claude Code's entry for the server. Claude Code missing, slow or failing changes nothing here.
  static func eraseOutsideTheDataFolder() async {
    @Dependency(\.keychainClient) var keychain
    @Dependency(\.commandClient) var commands
    @Dependency(\.fileClient) var files
    for account in await keychain.accounts(keychainService) {
      await keychain.delete(keychainService, account)
    }
    await keychain.delete(serverService, tokenAccount)
    // As Connect finds it: the user's shell tells its PATH, and Vortex looks for `claude` itself.
    guard let check = try? await commands.run(pathCommand, nil, [:], checkTime), !check.timedOut else { return }
    let path = markedPath(String(decoding: check.stdout, as: UTF8.self)) ?? ""
    for candidate in claudeCandidates(path: path, home: URL.homeDirectory) {
      guard let info = await files.info(candidate), !info.isDirectory, info.isExecutable else { continue }
      _ = try? await commands.run("\(shellQuoted(candidate.path)) mcp remove --scope user vortex", nil, [:], checkTime)
      return
    }
  }
}
