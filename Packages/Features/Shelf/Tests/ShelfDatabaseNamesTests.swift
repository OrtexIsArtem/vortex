import Testing
import VortexCore

@testable import FeatureShelf

/// Erase Data finds a feature's tables and migrations by its id: every name the migrator makes carries it.
struct ShelfDatabaseNamesTests {
  @Test
  func shelfTablesAndMigrationsCarryItsId() async throws {
    let names = try await ShelfItem.migrator.names()
    #expect(!names.tables.isEmpty)
    #expect(names.tables.allSatisfy { $0.hasPrefix("shelf_") }, "\(names.tables)")
    #expect(names.migrations.allSatisfy { $0.hasPrefix("shelf.") }, "\(names.migrations)")
  }
}
