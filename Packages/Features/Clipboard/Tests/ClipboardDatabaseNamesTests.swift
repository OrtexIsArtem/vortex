import Testing
import VortexCore

@testable import FeatureClipboard

/// Erase Data finds a feature's tables and migrations by its id: every name the migrator makes carries it.
struct ClipboardDatabaseNamesTests {
  @Test
  func clipboardTablesAndMigrationsCarryItsId() async throws {
    let names = try await ClipboardItem.migrator.names()
    #expect(!names.tables.isEmpty)
    #expect(names.tables.allSatisfy { $0.hasPrefix("clipboard_") }, "\(names.tables)")
    #expect(names.migrations.allSatisfy { $0.hasPrefix("clipboard.") }, "\(names.migrations)")
  }
}
