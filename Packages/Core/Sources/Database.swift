import Dependencies
import Foundation
import GRDB
import os

/// Where Vortex keeps its data: ~/Library/Application Support/Vortex. A backup is a copy of this folder.
public enum DataFolder {
  public static let url = URL.applicationSupportDirectory.appending(path: "Vortex", directoryHint: .isDirectory)
}

/// The one SQLite database of Vortex, DataFolder/vortex.sqlite.
///
/// Every feature keeps its own tables here, named after its id (`clipboard_item`), and creates them with its own
/// `DatabaseMigrator` whose migration names start with the id too (`clipboard.v1`). Migrators of different features
/// share the database without seeing each other's migrations.
public enum VortexDatabase {
  /// Opens the database file, creating it and its folder when needed.
  public static func open(at url: URL) throws -> DatabasePool {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var configuration = Configuration()
    configuration.label = "Vortex"
    // A Vortex taking over from one still quitting may open the file during its last write: wait for it.
    configuration.busyMode = .timeout(5)
    return try DatabasePool(path: url.path, configuration: configuration)
  }

  /// An empty database in memory, for tests and previews.
  public static func inMemory() -> DatabaseQueue {
    // Opening an in-memory database only fails when SQLite itself is broken.
    try! DatabaseQueue()
  }
}

extension DatabaseWriter {
  /// Creates or updates a feature's tables; does nothing when they are current. Call it before the feature's first query.
  public func migrate(_ migrator: DatabaseMigrator) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
      migrator.asyncMigrate(self) { result in
        continuation.resume(with: result.map { _ in })
      }
    }
  }
}

extension DependencyValues {
  /// The app's database. Use the async `read` and `write`, so queries never run on the main thread.
  /// Tests get an empty in-memory database.
  public var database: any DatabaseWriter {
    get { self[DatabaseKey.self] }
    set { self[DatabaseKey.self] = newValue }
  }

  /// Whether `database` is the file. False when the file couldn't be opened and features work in an empty database in
  /// memory until the next launch: they must not then remove files or values that have no row, as the rows are only
  /// out of reach. Reading it opens the database: read it in an effect, not on the main thread. Tests get true.
  public var databaseIsOnDisk: Bool {
    get { self[DatabaseIsOnDiskKey.self] }
    set { self[DatabaseIsOnDiskKey.self] = newValue }
  }
}

private enum DatabaseKey: DependencyKey {
  static let liveValue: any DatabaseWriter = opened.writer
  static var testValue: any DatabaseWriter { VortexDatabase.inMemory() }

  /// The file, opened once per launch, or an empty database in memory when it can't be.
  static let opened: (writer: any DatabaseWriter, isOnDisk: Bool) = {
    let url = DataFolder.url.appending(path: "vortex.sqlite")
    do {
      return (try VortexDatabase.open(at: url), true)
    } catch {
      // A broken file must not stop the app: features keep working in memory until the next launch.
      Logger(subsystem: "io.github.ortexisartem.vortex", category: "database")
        .error("Could not open \(url.path, privacy: .public): \(error, privacy: .public)")
      return (VortexDatabase.inMemory(), false)
    }
  }()
}

private enum DatabaseIsOnDiskKey: DependencyKey {
  static let liveValue = DatabaseKey.opened.isOnDisk
  static let testValue = true
}
