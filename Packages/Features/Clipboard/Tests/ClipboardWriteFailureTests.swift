import ComposableArchitecture
import Foundation
import GRDB
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureClipboard

/// Writes that fail: a batch lands whole or not at all, is written again after a pause until it lands, and a change
/// that can never be written doesn't stop the others.
extension ClipboardFeatureTests {
  /// Makes every write to the history fail with `failure`'s code while it holds one (busy, full…), as the database's
  /// state would: a TEMP trigger calls a function that throws it.
  func failWrites(_ failure: LockIsolated<ResultCode?>) throws {
    try ClipboardItem.migrator.migrate(database)
    try database.write { db in
      db.add(function: DatabaseFunction("vortexTestFailure", argumentCount: 0, pure: false) { _ in
        if let code = failure.value { throw DatabaseError(resultCode: code, message: "failing on purpose") }
        return nil
      })
      for event in ["INSERT", "UPDATE", "DELETE"] {
        try db.execute(sql: """
          CREATE TEMP TRIGGER fail\(event) BEFORE \(event) ON clipboard_item BEGIN SELECT vortexTestFailure(); END
          """)
      }
    }
  }

  func savedTexts() throws -> [String] {
    try savedHistory().map { item in
      if case let .text(text) = item.content { text } else { "" }
    }
  }

  @Test
  func theDeleteOfARowThatTurnedSecretLandsOnTheRetry() async throws {
    let failure = LockIsolated<ResultCode?>(nil)
    try failWrites(failure)
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text("hunter2"))
    await store.receive(\.copied)
    await store.receive(\.written)
    #expect(try rowCount() == 1)

    // The database is busy as the password manager copies it.
    failure.setValue(.SQLITE_BUSY)
    copy(.text("hunter2"), from: Self.passwords, concealed: true)
    await store.receive(\.copied)
    await store.receive(\.written)
    #expect(try rowCount() == 1)
    failure.setValue(nil)
    await clock.advance(by: .seconds(1))
    await store.send(.stop)
    await store.finish()
    #expect(try rowCount() == 0)
  }

  @Test
  func changesAfterAFailedInsertWaitForItAndAllLandInOrder() async throws {
    let failure = LockIsolated<ResultCode?>(.SQLITE_FULL)
    try failWrites(failure)
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text("typo"))
    await store.receive(\.copied)
    await store.receive(\.written)
    // Copied and deleted while the insert waits to be written again.
    copy(.text("kept"))
    await store.receive(\.copied)
    await store.send(.deleteTapped(uuid(0)))
    failure.setValue(nil)
    // Written again after the first pause, 1 s, with what came meanwhile, in order.
    await clock.advance(by: .seconds(1))
    await store.send(.stop)
    await store.finish()
    #expect(try savedTexts() == ["kept"])
  }

  @Test
  func memoryKeepsALongTextWholeUntilItsInsertLands() async throws {
    let failure = LockIsolated<ResultCode?>(.SQLITE_IOERR)
    try failWrites(failure)
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.text(Self.longText))
    await store.receive(\.copied)
    await store.receive(\.written)
    #expect(store.state.items.first?.content == .text(Self.longText))
    #expect(store.state.items.first?.isTruncated == false)
    // Still failing at the first retry: still whole.
    await clock.advance(by: .seconds(1))
    await store.receive(\.written)
    #expect(store.state.items.first?.isTruncated == false)
    failure.setValue(nil)
    await clock.advance(by: .seconds(2))
    await store.receive(\.written)
    #expect(store.state.items.first?.content == .text(Self.longTextStart))
    let id = try #require(store.state.items.first?.id)
    #expect(try await database.read { db in try ClipboardItem.wholeText(of: id, db) } == Self.longText)
    await store.send(.stop)
  }

  @Test
  func theQueueMovesPastAChangeThatCanNeverBeWritten() async throws {
    let failure = LockIsolated<ResultCode?>(.SQLITE_BUSY)
    try failWrites(failure)
    // This text breaks a constraint, whatever the database's state.
    let refused = ClipboardCopy.fingerprint(of: .text("refused"))
    try await database.write { db in
      try db.execute(sql: """
        CREATE TEMP TRIGGER refuse BEFORE INSERT ON clipboard_item WHEN NEW.fingerprint = '\(refused)'
        BEGIN SELECT RAISE(ABORT, 'refused on purpose'); END
        """)
    }
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    // Both wait for the busy database, then go in one batch.
    copy(.text("refused"))
    await store.receive(\.copied)
    await store.receive(\.written)
    copy(.text("after it"))
    await store.receive(\.copied)
    failure.setValue(nil)
    await clock.advance(by: .seconds(1))
    await store.receive(\.written)
    #expect(try savedTexts() == ["after it"])
    // Only the refused one was dropped: what comes next is written as usual.
    copy(.text("later"))
    await store.receive(\.copied)
    await store.receive(\.written)
    await store.send(.stop)
    await store.finish()
    #expect(try savedTexts() == ["later", "after it"])
    #expect(store.state.queuedWrites.isEmpty)
  }
}
