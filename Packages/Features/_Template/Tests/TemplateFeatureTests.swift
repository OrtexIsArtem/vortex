import ComposableArchitecture
import GRDB
import Testing
import VortexCore

@testable import FeatureTemplate

@MainActor
struct TemplateFeatureTests {
  @Test
  func incrementButtonTapped() async {
    let store = TestStore(initialState: TemplateFeature.State()) {
      TemplateFeature()
    }

    await store.send(.incrementButtonTapped) {
      $0.count = 1
    }
  }

  /// Once the feature keeps tables, prove they and their migrations carry its id, as Erase Data finds them by it:
  /// put the feature's own migrator here in place of this example.
  @Test
  func tablesAndMigrationsCarryTheFeatureId() async throws {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("template.v1") { db in
      try db.create(table: "template_item") { $0.autoIncrementedPrimaryKey("id") }
    }
    let names = try await migrator.names()
    #expect(names.tables.allSatisfy { $0.hasPrefix("template_") }, "\(names.tables)")
    #expect(names.migrations.allSatisfy { $0.hasPrefix("template.") }, "\(names.migrations)")
  }
}
