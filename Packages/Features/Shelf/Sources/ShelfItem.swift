import Foundation
import GRDB
import VortexCore
import VortexPlatform

/// Something put on the shelf.
public struct ShelfItem: Identifiable, Equatable, Sendable {
  public enum Content: Codable, Equatable, Sendable {
    /// The user's file or folder, kept by reference.
    case file(URL)
    /// A file the shelf keeps itself, see `ShelfItem.copiesFolder`: an image dropped without a file, or a file from
    /// Vortex's own data that could disappear with its owner. Deleted with the item.
    case copy(fileName: String)
    case text(String)
    case link(URL)
  }

  public var id: UUID
  public var content: Content
  public var addedAt: Date
  /// Pinned items stay past the shelf's 24 hours.
  public var isPinned = false

  /// Where the shelf's own copies live, one folder per item.
  static let copiesFolder = DataFolder.url.appending(path: "Shelf", directoryHint: .isDirectory)

  /// The file of a file or copy item.
  var fileURL: URL? {
    switch content {
    case let .file(url): url
    case let .copy(fileName): Self.copiesFolder.appending(path: id.uuidString).appending(path: fileName)
    case .text, .link: nil
    }
  }

  var isCopy: Bool {
    if case .copy = content { true } else { false }
  }

  /// What a drag of the item carries into another app.
  var dragItem: DragItem {
    switch content {
    case let .text(text): .text(text)
    case let .link(url): .link(url)
    case .file, .copy: .file(fileURL!)
    }
  }
}

// MARK: - Database

/// The shelf is a single table, `shelf_item`, saved whole after every change, with each item's place in `position`.
/// Rows this version can't read (written by a newer Vortex) are left as they are.
extension ShelfItem: Codable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "shelf_item"

  public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
    .uppercaseString
  }

  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("shelf.v1") { db in
      try db.create(table: databaseTableName) { table in
        table.primaryKey("id", .text)
        // JSON of `Content`.
        table.column("content", .text).notNull()
        table.column("addedAt", .datetime).notNull()
        table.column("isPinned", .boolean).notNull()
      }
    }
    migrator.registerMigration("shelf.v2") { db in
      try db.alter(table: databaseTableName) { table in
        table.add(column: "position", .integer).notNull().defaults(to: 0)
      }
    }
    return migrator
  }

  /// Every saved item in shelf order; rows this version can't read are skipped.
  static func fetchAllReadable(_ db: Database) throws -> [ShelfItem] {
    try Row.fetchAll(db, sql: "SELECT * FROM \(databaseTableName) ORDER BY position, rowid").compactMap { try? ShelfItem(row: $0) }
  }

  /// Ids of every saved row, readable or not.
  static func savedIDs(_ db: Database) throws -> Set<String> {
    try String.fetchSet(db, sql: "SELECT id FROM \(databaseTableName)")
  }

  /// Makes the saved shelf match `items`, in their order: writes them and deletes the other rows this version can read.
  static func save(_ items: [ShelfItem], in db: Database) throws {
    let kept = Set(items.map(\.id.uuidString))
    for id in try savedIDs(db) where !kept.contains(id) {
      let row = try Row.fetchOne(db, sql: "SELECT * FROM \(databaseTableName) WHERE id = ?", arguments: [id])
      guard let row, (try? ShelfItem(row: row)) != nil else { continue }
      try db.execute(sql: "DELETE FROM \(databaseTableName) WHERE id = ?", arguments: [id])
    }
    for (position, item) in items.enumerated() {
      try item.upsert(db)
      try db.execute(
        sql: "UPDATE \(databaseTableName) SET position = ? WHERE id = ?",
        arguments: [position, item.id.uuidString]
      )
    }
  }
}
