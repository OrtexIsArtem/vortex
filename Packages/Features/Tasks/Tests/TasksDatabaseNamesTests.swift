import Testing
import VortexCore

@testable import FeatureTasks

/// Erase Data finds a feature's tables and migrations by its id: every name the migrator makes carries it.
struct TasksDatabaseNamesTests {
  @Test
  func tasksTablesAndMigrationsCarryItsId() async throws {
    let names = try await TaskItem.migrator.names()
    #expect(!names.tables.isEmpty)
    #expect(names.tables.allSatisfy { $0.hasPrefix("tasks_") }, "\(names.tables)")
    #expect(names.migrations.allSatisfy { $0.hasPrefix("tasks.") }, "\(names.migrations)")
  }
}
