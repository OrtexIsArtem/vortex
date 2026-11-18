import Testing
import VortexCore

@testable import FeatureSecrets

/// Erase Data finds a feature's tables and migrations by its id: every name the migrator makes carries it.
struct SecretsDatabaseNamesTests {
  @Test
  func secretsTablesAndMigrationsCarryItsId() async throws {
    let names = try await SecretKey.migrator.names()
    #expect(!names.tables.isEmpty)
    #expect(names.tables.allSatisfy { $0.hasPrefix("secrets_") }, "\(names.tables)")
    #expect(names.migrations.allSatisfy { $0.hasPrefix("secrets.") }, "\(names.migrations)")
  }
}
