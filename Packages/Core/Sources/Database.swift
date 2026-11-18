import Dependencies
import Foundation
import GRDB
import os

/// Where Vortex keeps its data: ~/Library/Application Support/Vortex. A backup is a copy of this folder.
///
/// A debug build started with `--qa <name>` keeps everything in ~/Library/Application Support/Vortex QA/<name> instead,
/// so a QA run never touches the user's data; one started with a bad `--qa` stops before anything reads this.
public enum DataFolder {
  #if DEBUG
    public static let url = folder(in: .applicationSupportDirectory, qa: .current)
  #else
    public static let url = URL.applicationSupportDirectory.appending(path: "Vortex", directoryHint: .isDirectory)
  #endif
}

#if DEBUG
  extension DataFolder {
    /// The folder of all QA runs, one subfolder per name: Vortex QA, next to Vortex in `base`.
    public static func qaRoot(in base: URL) -> URL {
      base.appending(path: "Vortex QA", directoryHint: .isDirectory)
    }

    /// Vortex in `base`, or the QA run's own folder.
    static func folder(in base: URL, qa: QALaunch) -> URL {
      switch qa {
      case .none:
        return base.appending(path: "Vortex", directoryHint: .isDirectory)
      case let .named(name, _):
        return qaRoot(in: base).appending(path: name, directoryHint: .isDirectory)
      case .invalid:
        // Never the user's folder: the process stops here (main.swift stops it earlier).
        qa.stopIfInvalid()
        return qaRoot(in: base)
      }
    }
  }
#endif

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

extension DatabaseWriter {
  /// Erase Data: drops the feature's tables (`<id>_…`), full-text ones and views included, and forgets its
  /// migrations (`<id>.v…`), so the feature added again starts empty. Other features' tables stay, even where the name
  /// only looks alike: in the pattern `_` is a plain underscore.
  public func eraseFeature(_ id: FeatureID) async throws {
    let prefix = id.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "\\%")
      .replacingOccurrences(of: "_", with: "\\_")
    try await write { db in
      // Tables of the feature may point at each other: checked only once all of them are gone.
      try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
      let objects = try Row.fetchAll(
        db,
        sql: """
          SELECT type, name, sql FROM sqlite_master
          WHERE type IN ('table', 'view') AND name LIKE ? ESCAPE '\\'
          """,
        arguments: [prefix + "\\_%"]
      )
      // Views first, then full-text tables, which take their own shadow tables with them, then the rest.
      let order: (Row) -> Int = { row in
        let type: String = row["type"]
        let sql: String? = row["sql"]
        if type == "view" { return 0 }
        return sql?.uppercased().hasPrefix("CREATE VIRTUAL TABLE") == true ? 1 : 2
      }
      for object in objects.sorted(by: { order($0) < order($1) }) {
        let type: String = object["type"]
        let name: String = object["name"]
        try db.execute(sql: "DROP \(type == "view" ? "VIEW" : "TABLE") IF EXISTS \(name.quotedDatabaseIdentifier)")
      }
      if try db.tableExists("grdb_migrations") {
        try db.execute(
          sql: "DELETE FROM grdb_migrations WHERE identifier LIKE ? ESCAPE '\\'",
          arguments: [prefix + ".%"]
        )
      }
    }
  }
}

extension DatabaseMigrator {
  /// What the migrator makes on an empty database: its tables, views included, and its migrations, by name. A feature's
  /// test checks that every one of them starts with its id (`<id>_`, `<id>.`), so Erase Data finds them all.
  public func names() async throws -> (tables: [String], migrations: [String]) {
    let database = VortexDatabase.inMemory()
    try await database.migrate(self)
    return try await database.read { db in
      let tables = try String.fetchAll(
        db,
        sql: """
          SELECT name FROM sqlite_master
          WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\' AND name != 'grdb_migrations'
          ORDER BY name
          """
      )
      let migrations = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
      return (tables, migrations)
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
