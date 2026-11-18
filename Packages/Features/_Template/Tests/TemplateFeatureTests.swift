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

  /// The template's widget follows Home's rules: at most two widgets, each with one to three sizes, ids that start with
  /// the feature's id. A feature of yours keeps this test for its own widgets.
  @Test
  func templateWidgetsFollowTheRules() {
    let widgets = TemplateModule.makeHomeWidgets()
    #expect(!widgets.isEmpty)
    #expect(HomeWidget.problems(widgets, feature: TemplateModule.id).isEmpty)
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
