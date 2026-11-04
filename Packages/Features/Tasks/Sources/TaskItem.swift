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
  /// Where the framed part was on the screen, and the screen's size, in points, to mark the part on the whole screen;
  /// nil for tasks saved before they were kept.
  public var cropX: Double?
  public var cropY: Double?
  public var screenWidth: Double?
  public var screenHeight: Double?
  /// The text recognized on both pictures, for search; nil until recognition has run.
  public var text: String?

  public var isDone: Bool { completedAt != nil }

  /// Where the framed part lies on the whole screen, in fractions of its width and height; nil when not known.
  var cropArea: CGRect? {
    guard let cropX, let cropY, let screenWidth, let screenHeight, screenWidth > 0, screenHeight > 0 else { return nil }
    return CGRect(x: cropX / screenWidth, y: cropY / screenHeight, width: cropWidth / screenWidth, height: cropHeight / screenHeight)
  }

  /// The title as shown: an emptied one is "Task 13" again.
  var displayTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.defaultTitle(number: number) : title
  }

  /// The title as the row keeps it: empty for an untouched "Task 13" (or an emptied title), so it reads in whatever
  /// language Vortex speaks later; anything else as typed.
  var storedTitle: String {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty || title == Self.defaultTitle(number: number) ? "" : self.title
  }

  /// The task as its row keeps it, with `storedTitle`.
  var stored: TaskItem {
    var task = self
    task.title = storedTitle
    return task
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
    migrator.registerMigration("tasks.v2") { db in
      // Where the framed part was on the screen; empty for the tasks saved before.
      try db.alter(table: databaseTableName) { table in
        table.add(column: "cropX", .double)
        table.add(column: "cropY", .double)
        table.add(column: "screenWidth", .double)
        table.add(column: "screenHeight", .double)
      }
    }
    migrator.registerMigration("tasks.v3") { db in
      // Default titles saved before they were kept empty: the English one, and the Ukrainian one of Vortex 0.1.0, whose
      // word for a task 0.1.1 changed. Emptied, they read as "Task N" in the app's language of the day. A number of
      // 1000 or more was written with a group separator; such a title doesn't match and stays as it is.
      try db.execute(
        sql: "UPDATE \(databaseTableName) SET title = '' WHERE title = 'Task ' || number OR title = 'Задача ' || number"
      )
    }
    return migrator
  }

  /// Every saved task; rows this version can't read (written by a newer Vortex) are skipped. A title kept empty reads
  /// as "Task 13" in the app's language.
  static func fetchAllReadable(_ db: Database) throws -> [TaskItem] {
    try Row.fetchAll(db, sql: "SELECT * FROM \(databaseTableName)").compactMap { row in
      guard var task = try? TaskItem(row: row) else { return nil }
      task.title = task.displayTitle
      return task
    }
  }

  /// The highest number ever given.
  static func lastNumber(_ db: Database) throws -> Int {
    let counted = try Int.fetchOne(db, sql: "SELECT lastNumber FROM \(counterTable) WHERE id = 1") ?? 0
    let used = try Int.fetchOne(db, sql: "SELECT MAX(number) FROM \(databaseTableName)") ?? 0
    return max(counted, used)
  }

  /// Saves a new task under the next free number. When another Vortex took the number the task was shown with, it
  /// gets the next one, and an untouched default title follows. The row keeps `storedTitle`.
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
    try task.stored.insert(db)
    return task
  }
}
