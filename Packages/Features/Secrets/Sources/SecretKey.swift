import Foundation
import GRDB
import VortexCore

/// A key the user stored. Its value is in the keychain under `id`; here are its name and what is known about it.
public struct SecretKey: Identifiable, Equatable, Sendable {
  public var id: UUID
  /// What Claude writes to use it, as in {{prod-db}}: letters, digits, dot, dash and underscore; any case.
  public var name: String
  public var kind: KeyKind
  /// The user's words on what it is for, given to Claude with the name.
  public var note: String
  public var createdAt: Date
  /// When it deletes itself; nil keeps it.
  public var expiresAt: Date?
  public var lastUsedAt: Date?

  /// Names are what {{…}} holds: a letter or digit first, then also dots, dashes and underscores.
  static var namePattern: Regex<Substring> { /[A-Za-z0-9][A-Za-z0-9._\-]{0,63}/ }

  static func isValidName(_ name: String) -> Bool {
    name.wholeMatch(of: namePattern) != nil
  }

  func isExpired(at now: Date) -> Bool {
    expiresAt.map { $0 <= now } ?? false
  }
}

/// How long a new key lives.
public enum KeyLifetime: CaseIterable, Equatable, Sendable {
  case hour
  case endOfDay
  case forever

  func expiry(from now: Date, calendar: Calendar) -> Date? {
    switch self {
    case .hour:
      now.addingTimeInterval(3600)
    case .endOfDay:
      calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
    case .forever:
      nil
    }
  }
}

// MARK: - Database

/// Keys in `secrets_key`; values never reach the database.
extension SecretKey: Codable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "secrets_key"

  public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
    .uppercaseString
  }

  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("secrets.v1") { db in
      try db.create(table: databaseTableName) { table in
        table.primaryKey("id", .text)
        table.column("name", .text).notNull().unique().collate(.nocase)
        table.column("kind", .text).notNull()
        table.column("note", .text).notNull()
        table.column("createdAt", .datetime).notNull()
        table.column("expiresAt", .datetime)
        table.column("lastUsedAt", .datetime)
      }
      try db.create(table: "secrets_use") { table in
        table.primaryKey("id", .text)
        table.column("at", .datetime).notNull().indexed()
        // JSON array of names.
        table.column("keys", .text).notNull()
        table.column("client", .text).notNull()
        table.column("command", .text).notNull()
        table.column("outcome", .text).notNull()
        table.column("exitCode", .integer)
      }
    }
    // The log of uses is gone: Claude Code shows every command in its own history.
    migrator.registerMigration("secrets.v2") { db in
      try db.drop(table: "secrets_use")
    }
    return migrator
  }

  /// Every saved key; rows this version can't read (written by a newer Vortex) are skipped.
  static func fetchAllReadable(_ db: Database) throws -> [SecretKey] {
    try Row.fetchAll(db, sql: "SELECT * FROM \(databaseTableName) ORDER BY name").compactMap { try? SecretKey(row: $0) }
  }
}
