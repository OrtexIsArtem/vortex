import CryptoKit
import Foundation
import GRDB
import VortexCore
import VortexPlatform

/// One entry of the clipboard history.
public struct ClipboardItem: Identifiable, Equatable, Sendable {
  public enum Content: Codable, Equatable, Sendable {
    case text(String)
    case link(URL)
    /// An image copied without a file, kept as a PNG file in the data folder, see `ClipboardItem.imageURL`.
    case image(fileName: String)
    /// References to files and folders, never copies.
    case files([URL])
  }

  public var id: UUID
  public var content: Content
  public var source: AppInfo?
  public var copiedAt: Date
  public var isPinned = false
  /// Marked secret by the app it came from; shown hidden until the user reveals it.
  public var isConcealed = false
  /// Equal for equal content, so copying the same thing again moves the old item up instead of adding another.
  public var fingerprint: String

  /// Where images of the history live, one folder per item.
  static let imagesFolder = DataFolder.url.appending(path: "Clipboard", directoryHint: .isDirectory)

  /// The PNG file of an image item.
  var imageURL: URL? {
    guard case let .image(fileName) = content else { return nil }
    return Self.imagesFolder.appending(path: id.uuidString).appending(path: fileName)
  }

  /// Files the item depends on: the image file, or the referenced files.
  var fileURLs: [URL] {
    switch content {
    case .text, .link: []
    case .image: imageURL.map { [$0] } ?? []
    case let .files(urls): urls
    }
  }

  /// What a drag of the item carries into another app.
  var dragItems: [DragItem] {
    switch content {
    case let .text(text): [.text(text)]
    case let .link(url): [.link(url)]
    case .image, .files: fileURLs.map(DragItem.file)
    }
  }
}

/// A copy as the clipboard receives it: what was copied and its fingerprint, worked out off the main thread.
public struct ClipboardCopy: Equatable, Sendable {
  public var copy: PasteboardCopy
  public var fingerprint: String

  public init(_ copy: PasteboardCopy) {
    self.copy = copy
    fingerprint = Self.fingerprint(of: copy.content)
  }

  static func fingerprint(of content: PasteboardContent) -> String {
    func digest(_ data: Data) -> String {
      SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    switch content {
    case let .text(text): return "text:" + digest(Data(text.utf8))
    case let .link(url): return "link:" + digest(Data(url.absoluteString.utf8))
    case let .image(png): return "image:" + digest(png)
    case let .files(urls): return "files:" + digest(Data(urls.map(\.path).joined(separator: "\n").utf8))
    }
  }
}

// MARK: - Database

/// The history is a single table, `clipboard_item`, saved whole after every change: it holds a few dozen rows.
/// Rows this version can't read (written by a newer Vortex) are left as they are.
extension ClipboardItem: Codable, FetchableRecord, PersistableRecord {
  public static let databaseTableName = "clipboard_item"
  public static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
    .uppercaseString
  }

  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("clipboard.v1") { db in
      try db.create(table: databaseTableName) { table in
        table.primaryKey("id", .text)
        // JSON of `Content` and `AppInfo`.
        table.column("content", .text).notNull()
        table.column("source", .text)
        table.column("copiedAt", .datetime).notNull()
        table.column("isPinned", .boolean).notNull()
        table.column("isConcealed", .boolean).notNull()
        table.column("fingerprint", .text).notNull()
      }
    }
    return migrator
  }

  /// Every saved item; rows this version can't read are skipped.
  static func fetchAllReadable(_ db: Database) throws -> [ClipboardItem] {
    try Row.fetchAll(db, sql: "SELECT * FROM \(databaseTableName)").compactMap { try? ClipboardItem(row: $0) }
  }

  /// Ids of every saved row, readable or not.
  static func savedIDs(_ db: Database) throws -> Set<String> {
    try String.fetchSet(db, sql: "SELECT id FROM \(databaseTableName)")
  }

  /// Makes the saved history match `items`: writes them and deletes the other rows this version can read.
  static func save(_ items: [ClipboardItem], in db: Database) throws {
    let kept = Set(items.map(\.id.uuidString))
    for id in try savedIDs(db) where !kept.contains(id) {
      let row = try Row.fetchOne(db, sql: "SELECT * FROM \(databaseTableName) WHERE id = ?", arguments: [id])
      guard let row, (try? ClipboardItem(row: row)) != nil else { continue }
      try db.execute(sql: "DELETE FROM \(databaseTableName) WHERE id = ?", arguments: [id])
    }
    for item in items {
      try item.upsert(db)
    }
  }
}
