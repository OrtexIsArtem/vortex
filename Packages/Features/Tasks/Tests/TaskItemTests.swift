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
