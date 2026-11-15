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
  /// For a long text that is saved, only its start (`isTruncated`).
  public var content: Content
  public var source: AppInfo?
  public var copiedAt: Date
  public var isPinned = false
  /// Marked secret by the app it came from; shown hidden until the user reveals it.
  public var isConcealed = false
  /// Equal for equal content, so copying the same thing again moves the old item up instead of adding another.
  public var fingerprint: String
  /// What the item takes on disk: an image's PNG file, the UTF-8 of a text or a link, the paths of files.
  public var byteSize = 0
  /// `content` holds only the start of a long text, `previewBytes` of it; the whole text is in the database. Memory
  /// only.
  public var isTruncated = false

  /// A saved text longer than this, in UTF-8, is kept in memory only by its start.
  static let previewBytes = 4_096
  /// How much of a text search looks through.
  static let searchedBytes = 16_384

  /// Where images of the history live, one folder per item.
  static let imagesFolder = DataFolder.url.appending(path: "Clipboard", directoryHint: .isDirectory)

  /// The PNG file of an image item.
  var imageURL: URL? {
    guard case let .image(fileName) = content else { return nil }
    return Self.imagesFolder.appending(path: id.uuidString).appending(path: fileName)
  }

  var isImage: Bool {
    if case .image = content { true } else { false }
  }

  /// What the item takes on disk: a secret, kept in memory only, takes nothing.
  var storedBytes: Int {
    isConcealed ? 0 : byteSize
  }

  /// Files the item depends on: the image file, or the referenced files.
  var fileURLs: [URL] {
    switch content {
    case .text, .link: []
    case .image: imageURL.map { [$0] } ?? []
    case let .files(urls): urls
    }
  }

  /// What a drag of the item carries into another app. A secret carries nothing unless the user has it shown: wherever
  /// it is dropped it arrives as plain text or a file, and the shelf would save that to disk. A long text memory holds
  /// only the start of carries nothing until its whole text (`wholeText`) has been read.
  func dragItems(isRevealed: Bool, wholeText: String? = nil) -> [DragItem] {
    guard !isConcealed || isRevealed else { return [] }
    return switch content {
    case let .text(text): isTruncated ? wholeText.map { [.text($0)] } ?? [] : [.text(text)]
    case let .link(url): [.link(url)]
    case .image, .files: fileURLs.map(DragItem.file)
    }
  }

  /// The start of a text memory keeps once it is saved; nil when the text is short enough to keep whole.
  static func preview(of text: String) -> String? {
    text.utf8.count > previewBytes ? String(text.prefix(utf8Bytes: previewBytes)) : nil
  }

  /// What search looks through, in `searchKey` form: the app's name on the first line, then the first
  /// `searchedBytes` of a text, a link's address percent-decoded or the names of files. An image has only the app's
  /// until the text read from it follows (`HistoryWrite.text`, `imageSearchBody`). The app's name comes first so a
  /// copy from another app can change it in place (`HistoryWrite.update`).
  static func searchText(of content: Content, source: AppInfo?) -> String {
    let body: String = switch content {
    case let .text(text): String(text.prefix(utf8Bytes: searchedBytes))
    case let .link(url): url.absoluteString.removingPercentEncoding ?? url.absoluteString
    case .image: ""
    case let .files(urls):
      // The name on disk and, when it differs, the one Finder shows in the app's language (Downloads).
      urls.flatMap { url in
        let name = url.lastPathComponent
        let shown = FileName.shown(url)
        return shown == name ? [name] : [name, shown]
      }
      .joined(separator: "\n")
    }
    return appLine(source) + "\n" + searchKey(body)
  }

  /// The first line of `searchText`: the app's name.
  static func appLine(_ source: AppInfo?) -> String {
    searchKey(source?.name ?? "").replacingOccurrences(of: "\n", with: " ")
  }

  /// The form search compares in, the query and the saved text alike: lowercased in any alphabet, and composed, as a
  /// name from the file system may come decomposed.
  static func searchKey(_ text: String) -> String {
    text.lowercased().precomposedStringWithCanonicalMapping
  }

  /// Lowercase Cyrillic letters and the Latin letters they look like, which OCR takes for each other both ways ("TOKEH"
  /// for "ТОКЕН", "МСР" for "MCP"). Twins only in uppercase (В Н К М Т) are here too: keys are lowercase on both sides.
  private static let latinTwins: [Unicode.Scalar: Unicode.Scalar] = [
    "а": "a", "в": "b", "е": "e", "к": "k", "м": "m", "н": "h", "о": "o", "р": "p", "с": "c", "т": "t", "у": "y",
    "х": "x", "і": "i", "ј": "j", "ѕ": "s",
  ]

  /// A key in `searchKey` form with each Cyrillic letter that has a Latin twin written as that twin; everything else
  /// stays. The text read from an image is kept in this form, and a query's word is looked for in it in this form too,
  /// so look-alike letters never block a match.
  static func lookAlike(_ key: String) -> String {
    var folded = String.UnicodeScalarView()
    folded.append(contentsOf: key.unicodeScalars.lazy.map { latinTwins[$0] ?? $0 })
    return String(folded)
  }

  /// What search keeps of the text read from an image, after the app's line: its first `searchedBytes`, as of a text,
  /// in `searchKey` form with look-alike letters folded (`lookAlike`).
  static func imageSearchBody(_ text: String) -> String {
    lookAlike(searchKey(String(text.prefix(utf8Bytes: searchedBytes))))
  }
}

/// A copy as the clipboard receives it: what was copied, its fingerprint and its size, worked out off the main thread.
public struct ClipboardCopy: Equatable, Sendable {
  public var copy: PasteboardCopy
  public var fingerprint: String
  /// What it takes on disk once saved (`ClipboardItem.byteSize`).
  public var byteSize: Int

  public init(_ copy: PasteboardCopy) {
    self.copy = copy
    fingerprint = Self.fingerprint(of: copy.content)
    byteSize = Self.byteSize(of: copy.content)
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

  static func byteSize(of content: PasteboardContent) -> Int {
    switch content {
    case let .text(text): text.utf8.count
    case let .link(url): url.absoluteString.utf8.count
    case let .image(png): png.count
    case let .files(urls): urls.reduce(0) { $0 + $1.path.utf8.count }
    }
  }
}

extension String {
  /// The longest start of the text that takes at most `bytes` in UTF-8, cut between two characters.
  func prefix(utf8Bytes bytes: Int) -> Substring {
    guard utf8.count > bytes else { return self[...] }
    var end = utf8.index(startIndex, offsetBy: bytes)
    while end.samePosition(in: self) == nil {
      end = utf8.index(before: end)
    }
    return self[..<end]
  }
}

// MARK: - Database

/// The history is one table, `clipboard_item`, changed one row at a time (`HistoryWrite`). Rows this version can't read
/// (written by a newer Vortex) are skipped when loading and never changed or deleted: every write names its rows by id.
extension ClipboardItem {
  static let databaseTableName = "clipboard_item"

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
    migrator.registerMigration("clipboard.v2") { db in
      // Rows saved before have 0, NULL and '' here until the load completes them (`complete`).
      try db.alter(table: databaseTableName) { table in
        table.add(column: "byteSize", .integer).notNull().defaults(to: 0)
        // The start of a text longer than `previewBytes`, which is what memory keeps of it; NULL for anything else.
        table.add(column: "preview", .text)
        table.add(column: "searchText", .text).notNull().defaults(to: "")
      }
      try db.create(index: "clipboard_item_on_copiedAt", on: databaseTableName, columns: ["copiedAt"])
    }
    return migrator
  }

  private struct Unreadable: Error {}

  /// Every saved item this version can read, pinned first, newest first. A long text comes back as its start
  /// (`isTruncated`): its whole text is not even read.
  static func fetchAllReadable(_ db: Database) throws -> [ClipboardItem] {
    let decoder = JSONDecoder()
    // Most items share a few apps: each is decoded once.
    var sources: [String: AppInfo] = [:]
    var items: [ClipboardItem] = []
    let rows = try Row.fetchCursor(db, sql: """
      SELECT id, CASE WHEN preview IS NULL THEN content END AS content, preview, source, copiedAt, isPinned,
        isConcealed, fingerprint, byteSize
      FROM \(databaseTableName)
      ORDER BY isPinned DESC, copiedAt DESC
      """)
    while let row = try rows.next() {
      guard let item = try? ClipboardItem(row: row, decoder: decoder, sources: &sources) else { continue }
      items.append(item)
    }
    return items
  }

  private init(row: Row, decoder: JSONDecoder, sources: inout [String: AppInfo]) throws {
    guard let id = UUID(uuidString: try row.decode(String.self, forColumn: "id")) else { throw Unreadable() }
    self.id = id
    fingerprint = try row.decode(String.self, forColumn: "fingerprint")
    if let preview = try row.decode(String?.self, forColumn: "preview") {
      // Only a text has a preview; a row whose fingerprint says otherwise is a newer Vortex's.
      guard fingerprint.hasPrefix("text:") else { throw Unreadable() }
      content = .text(preview)
      isTruncated = true
    } else {
      content = try decoder.decode(Content.self, from: try row.decode(Data.self, forColumn: "content"))
    }
    if let json = try row.decode(String?.self, forColumn: "source") {
      if let known = sources[json] {
        source = known
      } else {
        let decoded = try decoder.decode(AppInfo.self, from: Data(json.utf8))
        sources[json] = decoded
        source = decoded
      }
    }
    copiedAt = try row.decode(Date.self, forColumn: "copiedAt")
    isPinned = try row.decode(Bool.self, forColumn: "isPinned")
    isConcealed = try row.decode(Bool.self, forColumn: "isConcealed")
    byteSize = try row.decode(Int.self, forColumn: "byteSize")
  }

  /// Ids of every saved row, readable or not.
  static func savedIDs(_ db: Database) throws -> Set<String> {
    try String.fetchSet(db, sql: "SELECT id FROM \(databaseTableName)")
  }

  /// Ids of the saved items whose search text holds every word (`searchText`), pinned first, newest first. A secret has
  /// no row, so it is never found. The text read from an image is kept with look-alike letters folded
  /// (`imageSearchBody`), so in that text a word is also looked for folded (`lookAlike`); the app's name, a text, a link
  /// or files are matched only as typed.
  static func search(_ words: [String], _ db: Database) throws -> [ID] {
    var conditions: [String] = []
    var arguments: [String] = []
    for word in words {
      let folded = lookAlike(word)
      if folded == word {
        conditions.append("instr(searchText, ?) > 0")
        arguments.append(word)
      } else {
        // An image's fingerprint starts with "image:" (`ClipboardCopy.fingerprint`); the text read from it follows the
        // app's line, which always ends in a line break (`searchText(of:source:)`).
        conditions.append("""
          (instr(searchText, ?) > 0 OR (substr(fingerprint, 1, 6) = 'image:' \
          AND instr(substr(searchText, instr(searchText, char(10)) + 1), ?) > 0))
          """)
        arguments += [word, folded]
      }
    }
    return try String.fetchAll(
      db,
      sql: """
        SELECT id FROM \(databaseTableName) WHERE \(conditions.joined(separator: " AND "))
        ORDER BY isPinned DESC, copiedAt DESC
        """,
      arguments: StatementArguments(arguments)
    )
    .compactMap(UUID.init(uuidString:))
  }

  /// The whole text of a long one, whose start alone is in memory.
  static func wholeText(of id: ID, _ db: Database) throws -> String {
    let json = try Data.fetchOne(
      db,
      sql: "SELECT content FROM \(databaseTableName) WHERE id = ?",
      arguments: [id.uuidString]
    )
    guard let json, case let .text(text) = try JSONDecoder().decode(Content.self, from: json) else { throw Unreadable() }
    return text
  }

  /// Rows saved before `clipboard.v2`, or since by an older Vortex, have no size (0), preview or search text: works
  /// them out from the items as loaded, which then hold their whole content, and writes them. An image's size is its
  /// file's, read through `files`, and its search text keeps what follows the app's line: the text read from it.
  /// Memory then keeps a long text by its start. Called once the history is read.
  static func complete(_ items: inout [ClipboardItem], files: FileClient, in database: any DatabaseWriter) async throws {
    struct Completion: Sendable {
      var index: Int
      var byteSize: Int
      var preview: String?
      /// The whole search text; for an image only the app's line, as what follows it stays (`keepsBody`).
      var searchText: String
      var keepsBody: Bool
    }
    var completions: [Completion] = []
    for (index, item) in items.enumerated() where item.byteSize == 0 && !item.isTruncated {
      var byteSize = 0
      var preview: String?
      switch item.content {
      case let .text(text):
        byteSize = text.utf8.count
        preview = Self.preview(of: text)
      case let .link(url):
        byteSize = url.absoluteString.utf8.count
      case .image:
        // Stays 0 while the file is missing, so it is read again at the next launch.
        if let url = item.imageURL, let size = await files.info(url)?.size {
          byteSize = Int(size)
        }
      case let .files(urls):
        byteSize = urls.reduce(0) { $0 + $1.path.utf8.count }
      }
      completions.append(
        Completion(
          index: index,
          byteSize: byteSize,
          preview: preview,
          searchText: item.isImage ? appLine(item.source) : searchText(of: item.content, source: item.source),
          keepsBody: item.isImage
        )
      )
    }
    guard !completions.isEmpty else { return }
    let ids = completions.map { items[$0.index].id.uuidString }
    try await database.write { [completions] db in
      let statement = try db.cachedStatement(
        sql: "UPDATE \(databaseTableName) SET byteSize = ?, preview = ?, searchText = ? WHERE id = ?"
      )
      // The app's line, then whatever follows it now, as `HistoryWrite.update` writes it.
      let keepingBody = try db.cachedStatement(sql: """
        UPDATE \(databaseTableName)
        SET byteSize = ?, preview = ?, searchText = ? || char(10) || substr(searchText, instr(searchText, char(10)) + 1)
        WHERE id = ?
        """)
      for (completion, id) in zip(completions, ids) {
        try (completion.keepsBody ? keepingBody : statement)
          .execute(arguments: [completion.byteSize, completion.preview, completion.searchText, id])
      }
    }
    for completion in completions {
      items[completion.index].byteSize = completion.byteSize
      if let preview = completion.preview {
        items[completion.index].content = .text(preview)
        items[completion.index].isTruncated = true
      }
    }
  }
}

/// A change to the saved history, one row each, named by id. The reducer queues them in the order it makes them and
/// they are written in that order, a batch at a time (`ClipboardFeature.writeQueued`).
enum HistoryWrite: Equatable, Sendable {
  /// A new item, whole, with the columns worked out from it. Never a secret.
  case insert(ClipboardItem)
  /// What changes in a saved item: when and where it was copied (with the app in its search text), and its pin.
  /// Never its content, which memory may hold only the start of.
  case update(ClipboardItem)
  /// Rows of items that are gone; their image folders go once the rows have.
  case delete([ClipboardItem.ID], folders: [URL])
  /// The text read from an image, in `ClipboardItem.imageSearchBody` form: it follows the app's line of the search
  /// text, which stays. Queued once, after the image's insert.
  case text(ClipboardItem.ID, body: String)

  /// Writes a batch; the first change that fails stops it, so in a transaction the batch lands whole or not at all.
  /// Returns the start memory keeps of each long text inserted, and the folders whose rows are gone.
  static func apply(_ batch: [HistoryWrite], _ db: Database) throws -> (previews: [ClipboardItem.ID: String], folders: [URL]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    var previews: [ClipboardItem.ID: String] = [:]
    var folders: [URL] = []
    for write in batch {
      switch write {
      case let .insert(item):
        // The reducer never queues a secret; this holds even if it did.
        guard !item.isConcealed else { continue }
        let preview = item.content.text.flatMap(ClipboardItem.preview(of:))
        try db.execute(
          sql: """
            INSERT INTO \(ClipboardItem.databaseTableName)
              (id, content, source, copiedAt, isPinned, isConcealed, fingerprint, byteSize, preview, searchText)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
          arguments: [
            item.id.uuidString,
            String(decoding: try encoder.encode(item.content), as: UTF8.self),
            try item.source.map { String(decoding: try encoder.encode($0), as: UTF8.self) },
            item.copiedAt,
            item.isPinned,
            item.isConcealed,
            item.fingerprint,
            item.byteSize,
            preview,
            ClipboardItem.searchText(of: item.content, source: item.source),
          ]
        )
        previews[item.id] = preview
      case let .update(item):
        guard !item.isConcealed else { continue }
        // The app's name is the first line of the search text: only that line changes. (A row with no line yet
        // keeps what it has after it; the next launch completes it.)
        try db.execute(
          sql: """
            UPDATE \(ClipboardItem.databaseTableName)
            SET copiedAt = ?, source = ?, isPinned = ?,
              searchText = ? || char(10) || substr(searchText, instr(searchText, char(10)) + 1)
            WHERE id = ?
            """,
          arguments: [
            item.copiedAt,
            try item.source.map { String(decoding: try encoder.encode($0), as: UTF8.self) },
            item.isPinned,
            ClipboardItem.appLine(item.source),
            item.id.uuidString,
          ]
        )
      case let .delete(ids, removedFolders):
        let statement = try db.cachedStatement(sql: "DELETE FROM \(ClipboardItem.databaseTableName) WHERE id = ?")
        for id in ids {
          try statement.execute(arguments: [id.uuidString])
        }
        folders += removedFolders
      case let .text(id, body):
        try db.execute(
          sql: """
            UPDATE \(ClipboardItem.databaseTableName)
            SET searchText = substr(searchText, 1, instr(searchText, char(10))) || ?
            WHERE id = ?
            """,
          arguments: [body, id.uuidString]
        )
      }
    }
    return (previews, folders)
  }

  /// Whether a change can never be written, whatever the database's state: it breaks a constraint, SQLite refuses its
  /// values, or it doesn't encode. Any other failure (busy, locked, full, read-only, I/O, a file it can't open) comes
  /// from the database and may pass: the change is written again later.
  static func isRefusedForGood(_ error: any Error) -> Bool {
    if error is CancellationError { return false }
    guard let error = error as? DatabaseError else { return true }
    switch error.resultCode {
    case .SQLITE_CONSTRAINT, .SQLITE_MISMATCH, .SQLITE_TOOBIG, .SQLITE_RANGE: return true
    default: return false
    }
  }
}

extension ClipboardItem.Content {
  /// The text of a text item.
  var text: String? {
    if case let .text(text) = self { text } else { nil }
  }
}
