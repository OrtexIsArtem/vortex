import Foundation
import GRDB
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureTasks

struct TaskItemTests {
  func task(number: Int, title: String? = nil) -> TaskItem {
    TaskItem(
      id: UUID(),
      number: number,
      title: title ?? TaskItem.defaultTitle(number: number),
      priority: .low,
      createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
      completedAt: nil,
      source: FrontWindow(app: AppInfo(bundleID: "ru.keepcoder.Telegram", name: "Telegram"), windowTitle: "mobile-team"),
      cropWidth: 300,
      cropHeight: 120,
      text: nil
    )
  }

  @Test
  func numbersAreNeverGivenTwiceEvenAfterTheHighestIsDeleted() async throws {
    let database = VortexDatabase.inMemory()
    try await database.migrate(TaskItem.migrator)
    let first = try await database.write { db in try TaskItem.insertNew(task(number: 1), db) }
    let second = try await database.write { db in try TaskItem.insertNew(task(number: 2), db) }
    #expect(first.number == 1)
    #expect(second.number == 2)
    _ = try await database.write { db in try second.delete(db) }
    #expect(try await database.read { db in try TaskItem.lastNumber(db) } == 2)
    let third = try await database.write { db in try TaskItem.insertNew(task(number: 2), db) }
    #expect(third.number == 3)
    // Shown as "Task 2", saved as the third: the untouched default title follows the number.
    #expect(third.title == TaskItem.defaultTitle(number: 3))
  }

  /// An untouched "Task N" is kept empty, so after a change of language it reads in the new one, as a new task's does;
  /// a typed title is kept as typed.
  @Test
  func anUntouchedDefaultTitleIsKeptEmptyAndReadsAsTheDefault() async throws {
    let database = VortexDatabase.inMemory()
    try await database.migrate(TaskItem.migrator)
    let untouched = try await database.write { db in try TaskItem.insertNew(task(number: 1), db) }
    _ = try await database.write { db in try TaskItem.insertNew(task(number: 2, title: "Fix the pay button"), db) }
    #expect(untouched.title == TaskItem.defaultTitle(number: 1))
    let kept = try await database.read { db in try String.fetchAll(db, sql: "SELECT title FROM tasks_task ORDER BY number") }
    #expect(kept == ["", "Fix the pay button"])
    let read = try await database.read { db in try TaskItem.fetchAllReadable(db) }.sorted { $0.number < $1.number }
    #expect(read.map(\.title) == [TaskItem.defaultTitle(number: 1), "Fix the pay button"])
  }

  /// Tasks saved before default titles were kept empty kept them as text, in English or in Vortex 0.1.0's Ukrainian:
  /// `tasks.v3` empties those, so they read as the default of the day. Other titles stay, also one that names another
  /// task's number, and the 1000th, saved with a group separator, as it was.
  @Test
  func oldDefaultTitlesAreEmptiedAndReadAsTheDefault() async throws {
    let database = VortexDatabase.inMemory()
    try TaskItem.migrator.migrate(database, upTo: "tasks.v1")
    let source = String(decoding: try JSONEncoder().encode(task(number: 1).source), as: UTF8.self)
    let saved: [(Int, String)] = [
      (1, "Task 1"),
      (2, "Задача 2"),
      (3, "Task 7"),
      (4, "Fix the pay button"),
      (5, "Задача 5 і 6"),
      (1000, "Задача 1\u{00A0}000"),
    ]
    try await database.write { db in
      for (number, title) in saved {
        try db.execute(
          sql: """
            INSERT INTO tasks_task (id, number, title, priority, createdAt, source, cropWidth, cropHeight)
            VALUES (?, ?, ?, 0, ?, ?, 300, 120)
            """,
          arguments: [UUID().uuidString, number, title, Date(timeIntervalSinceReferenceDate: 800_000_000), source]
        )
      }
    }
    try await database.migrate(TaskItem.migrator)
    let kept = try await database.read { db in try String.fetchAll(db, sql: "SELECT title FROM tasks_task ORDER BY number") }
    #expect(kept == ["", "", "Task 7", "Fix the pay button", "Задача 5 і 6", "Задача 1\u{00A0}000"])
    let read = try await database.read { db in try TaskItem.fetchAllReadable(db) }.sorted { $0.number < $1.number }
    #expect(read.prefix(2).map(\.title) == [TaskItem.defaultTitle(number: 1), TaskItem.defaultTitle(number: 2)])
    #expect(read.dropFirst(2).map(\.title) == ["Task 7", "Fix the pay button", "Задача 5 і 6", "Задача 1\u{00A0}000"])
  }

  @Test
  func aTitleTheUserTypedStaysWhenTheNumberMoves() async throws {
    let database = VortexDatabase.inMemory()
    try await database.migrate(TaskItem.migrator)
    _ = try await database.write { db in try TaskItem.insertNew(task(number: 1), db) }
    let typed = try await database.write { db in try TaskItem.insertNew(task(number: 1, title: "Fix the pay button"), db) }
    #expect(typed.number == 2)
    #expect(typed.title == "Fix the pay button")
  }

  @Test
  func whereThePartWasOnTheScreenReadsBackAsFractionsOfIt() async throws {
    let database = VortexDatabase.inMemory()
    try await database.migrate(TaskItem.migrator)
    var placed = task(number: 1)
    placed.cropX = 30
    placed.cropY = 40
    placed.screenWidth = 1500
    placed.screenHeight = 1000
    let inserted = try await database.write { [placed] db in try TaskItem.insertNew(placed, db) }
    let read = try await database.read { db in try TaskItem.fetchAllReadable(db) }
    #expect(read == [inserted])
    #expect(read.first?.cropArea == CGRect(x: 0.02, y: 0.04, width: 0.2, height: 0.12))
  }

  @Test
  func aTaskSavedBeforeThePlaceWasKeptReadsBackWithoutIt() async throws {
    let database = VortexDatabase.inMemory()
    try TaskItem.migrator.migrate(database, upTo: "tasks.v1")
    let source = String(decoding: try JSONEncoder().encode(task(number: 1).source), as: UTF8.self)
    try await database.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks_task (id, number, title, priority, createdAt, source, cropWidth, cropHeight)
          VALUES (?, 1, 'Old', 0, ?, ?, 300, 120)
          """,
        arguments: [UUID().uuidString, Date(timeIntervalSinceReferenceDate: 800_000_000), source]
      )
    }
    try await database.migrate(TaskItem.migrator)
    let read = try await database.read { db in try TaskItem.fetchAllReadable(db) }
    #expect(read.map(\.title) == ["Old"])
    #expect(read.first?.cropWidth == 300)
    #expect(read.first?.cropArea == nil)
  }

  @Test
  func aSavedTaskReadsBackWithItsSource() async throws {
    let database = VortexDatabase.inMemory()
    try await database.migrate(TaskItem.migrator)
    var saved = task(number: 1)
    saved.source.url = URL(string: "https://example.com/page")
    saved.text = "hello"
    let inserted = try await database.write { [saved] db in try TaskItem.insertNew(saved, db) }
    let read = try await database.read { db in try TaskItem.fetchAllReadable(db) }
    #expect(read == [inserted])
  }
}
