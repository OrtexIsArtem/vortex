import Foundation
import GRDB
import VortexCore
import VortexPlatform

/// A task: the part of the screen the user framed, the whole screen at that moment, and where it came from.
public struct TaskItem: Identifiable, Equatable, Sendable {
  public enum Priority: Int, Codable, CaseIterable, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  public var id: UUID
  /// Shown in "Task 13". Never given again, also after the task is deleted.
  public var number: Int
  public var title: String
  public var priority: Priority
  public var createdAt: Date
  /// When it was marked done; nil while it is active.
  public var completedAt: Date?
  /// The app, its window title and the page address, as they were at the capture.
  public var source: FrontWindow
  /// The framed part's size in points, to lay it out before the picture loads.
  public var cropWidth: Double
  public var cropHeight: Double
  /// The text recognized on both pictures, for search; nil until recognition has run.
  public var text: String?

  public var isDone: Bool { completedAt != nil }

  /// The title as shown and saved: an emptied one is "Task 13" again.
  var displayTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultTitle(number: number) : title
  }

  /// The pictures of every task, one folder per task.
  static let folder = DataFolder.url.appending(path: "Tasks", directoryHint: .isDirectory)

  var folderURL: URL { Self.folder.appending(path: id.uuidString, directoryHint: .isDirectory) }
  /// The framed part, PNG.
  var cropURL: URL { folderURL.appending(path: "crop.png") }
  /// The whole screen, HEIC.
  var screenURL: URL { folderURL.appending(path: "screen.heic") }

  /// "Task 13", the title a new task gets.
  static func defaultTitle(number: Int) -> String {
    String(localized: "Task \(number)", bundle: .module)
  }
}

// MARK: - Database

/// Tasks live in `tasks_task`, one row each, written as they change. `tasks_counter` keeps the last number given, so
/// numbers are never given twice even when the task that had the highest one is gone.
extension TaskItem: Codable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "tasks_task"
  static let counterTable = "tasks_counter"

  public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
    .uppercaseString
  }

  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("tasks.v1") { db in
      try db.create(table: databaseTableName) { table in
        table.primaryKey("id", .text)
        table.column("number", .integer).notNull().unique()
        table.column("title", .text).notNull()
        table.column("priority", .integer).notNull()
        table.column("createdAt", .datetime).notNull()
        table.column("completedAt", .datetime)
        // JSON of `FrontWindow`.
        table.column("source", .text).notNull()
        table.column("cropWidth", .double).notNull()
        table.column("cropHeight", .double).notNull()
        table.column("text", .text)
      }
      try db.create(table: counterTable) { table in
        table.primaryKey("id", .integer).check { $0 == 1 }
        table.column("lastNumber", .integer).notNull()
      }
    }
    return migrator
  }

  /// Every saved task; rows this version can't read (written by a newer Vortex) are skipped.
  static func fetchAllReadable(_ db: Database) throws -> [TaskItem] {
    try Row.fetchAll(db, sql: "SELECT * FROM \(databaseTableName)").compactMap { try? TaskItem(row: $0) }
  }

  /// The highest number ever given.
  static func lastNumber(_ db: Database) throws -> Int {
    let counted = try Int.fetchOne(db, sql: "SELECT lastNumber FROM \(counterTable) WHERE id = 1") ?? 0
    let used = try Int.fetchOne(db, sql: "SELECT MAX(number) FROM \(databaseTableName)") ?? 0
    return max(counted, used)
  }

  /// Saves a new task under the next free number. When another Vortex took the number the task was shown with, it
  /// gets the next one, and an untouched default title follows.
  static func insertNew(_ task: TaskItem, _ db: Database) throws -> TaskItem {
    var task = task
    let number = max(task.number, try lastNumber(db) + 1)
    if number != task.number, task.title == defaultTitle(number: task.number) {
      task.title = defaultTitle(number: number)
    }
    task.number = number
    try db.execute(
      sql: """
        INSERT INTO \(counterTable) (id, lastNumber) VALUES (1, ?)
        ON CONFLICT(id) DO UPDATE SET lastNumber = MAX(lastNumber, excluded.lastNumber)
        """,
      arguments: [number]
    )
    try task.insert(db)
    return task
  }
}
