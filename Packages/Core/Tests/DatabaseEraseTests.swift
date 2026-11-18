import Foundation
import GRDB
import Testing

@testable import VortexCore

struct DatabaseEraseTests {
  /// Erase Data drops the feature's tables, full-text ones and those its other tables point to included, and forgets
  /// its migrations; another feature's tables, even one whose name only looks alike, stay.
  @Test
  func erasingAFeatureDropsOnlyItsTablesAndMigrations() async throws {
    let database = VortexDatabase.inMemory()
    var clipboard = DatabaseMigrator()
    clipboard.registerMigration("clipboard.v1") { db in
      try db.create(table: "clipboard_item") { table in
        table.autoIncrementedPrimaryKey("id")
        table.column("text", .text)
      }
      try db.create(table: "clipboard_pin") { table in
        table.autoIncrementedPrimaryKey("id")
        table.belongsTo("clipboard_item")
      }
      try db.create(virtualTable: "clipboard_search", using: FTS5()) { $0.column("text") }
    }
    var shelf = DatabaseMigrator()
    shelf.registerMigration("shelf.v1") { db in
      try db.create(table: "shelf_item") { $0.autoIncrementedPrimaryKey("id") }
      // Not the clipboard's: in the name pattern `_` is a plain underscore.
      try db.create(table: "clipboardXitem") { $0.autoIncrementedPrimaryKey("id") }
    }
    try await database.migrate(clipboard)
    try await database.migrate(shelf)
    try await database.write { db in
      try db.execute(sql: "INSERT INTO clipboard_item (text) VALUES ('a')")
      try db.execute(sql: "INSERT INTO clipboard_pin (clipboard_itemId) VALUES (1)")
    }

    try await database.eraseFeature("clipboard")

    let tables = try await database.read { db in
      try String.fetchAll(
        db,
        sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite%' AND name != 'grdb_migrations' ORDER BY name"
      )
    }
    #expect(tables == ["clipboardXitem", "shelf_item"])
    let migrations = try await database.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier") }
    #expect(migrations == ["shelf.v1"])
    // Added again, it starts empty.
    try await database.migrate(clipboard)
    #expect(try await database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM clipboard_item") } == 0)
  }

  /// A feature keeps data in the database once its migrations ran, even with no file of its own, until it is erased;
  /// another feature's data doesn't count.
  @Test
  func aFeatureKeepsDataOnceItsMigrationsRanUntilErased() async throws {
    let database = VortexDatabase.inMemory()
    #expect(try await !database.keepsFeatureData("clipboard"))
    var clipboard = DatabaseMigrator()
    clipboard.registerMigration("clipboard.v1") { db in
      try db.create(table: "clipboard_item") { $0.autoIncrementedPrimaryKey("id") }
    }
    try await database.migrate(clipboard)
    #expect(try await database.keepsFeatureData("clipboard"))
    #expect(try await !database.keepsFeatureData("shelf"))
    try await database.eraseFeature("clipboard")
    #expect(try await !database.keepsFeatureData("clipboard"))
  }

  /// An id with `_` in it matches only itself, in table names and in migration names alike.
  @Test
  func anUnderscoreInTheIdMatchesOnlyItself() async throws {
    let database = VortexDatabase.inMemory()
    for id in ["a_b", "aXb"] {
      var migrator = DatabaseMigrator()
      migrator.registerMigration("\(id).v1") { db in
        try db.create(table: "\(id)_item") { $0.autoIncrementedPrimaryKey("id") }
      }
      try await database.migrate(migrator)
    }
    try await database.eraseFeature("a_b")
    let tables = try await database.read { db in
      try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE '%item' ORDER BY name")
    }
    #expect(tables == ["aXb_item"])
    let migrations = try await database.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") }
    #expect(migrations == ["aXb.v1"])
  }

  /// A feature that never made a table erases nothing, even before any migration ran.
  @Test
  func erasingAFeatureWithoutTablesChangesNothing() async throws {
    let database = VortexDatabase.inMemory()
    try await database.eraseFeature("timer")
    #expect(try await database.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master") } == [])
  }
}
