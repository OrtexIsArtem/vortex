import ComposableArchitecture
import Foundation
import GRDB
import os
import VortexCore
import VortexPlatform

/// History of what the user copies: the last ten items plus pinned ones, saved across launches.
@Reducer
public struct ClipboardFeature: Sendable {
  /// Unpinned items kept; pinned ones come on top of these.
  static let historyLimit = 10

  /// The whole text of a long item, whose start alone is in memory, read for a drag.
  struct WholeText: Equatable {
    var id: ClipboardItem.ID
    var text: String
  }

  @ObservableState
  public struct State: Equatable {
    /// Pinned items first, then the others; newest first in both groups (`displayOrder`).
    public var items: IdentifiedArrayOf<ClipboardItem> = []
    var isLoaded = false
    /// False when the saved history could not be read: this session keeps it in memory only, so nothing on disk is
    /// overwritten.
    var savesToDisk = true
    /// Changes waiting to be written, in the order they were made; they go once the batch being written is in.
    var queuedWrites: [HistoryWrite] = []
    var isWriting = false
    /// The whole text of the long item the pointer was last over, so it drags out in full.
    var wholeText: WholeText?
    /// Items whose files are gone.
    var unavailable: Set<ClipboardItem.ID> = []
    /// Concealed items the user is looking at; hidden again whenever the window opens.
    var revealed: Set<ClipboardItem.ID> = []
    /// The item just copied again, marked for a moment.
    var justCopied: ClipboardItem.ID?
    /// Running apps, offered when the user adds an app to ignore.
    var runningApps: [AppInfo] = []
    @Shared(.clipboardSettings) var settings
    /// What macOS says about Paste from Other Apps, read by the shell: the settings row, and no recording while it
    /// reads `notGranted`.
    @SharedReader(.permissionStatuses) var permissionStatuses

    public init() {}
  }

  public enum Action: Equatable, Sendable {
    case start
    case stop
    /// The saved history, read and ordered off the main thread.
    case loaded(IdentifiedArrayOf<ClipboardItem>)
    case loadFailed
    /// A batch of writes is in the database. Memory keeps the long texts it inserted by their start from now on.
    case written(previews: [ClipboardItem.ID: String])
    /// The pointer came over a card or a Home row: a long text's whole text is read, so it can be dragged out.
    case itemHovered(ClipboardItem.ID)
    case wholeTextRead(ClipboardItem.ID, String)
    case copied(ClipboardCopy)
    /// Something dropped on the clipboard on Home: copied, as if the user had copied it.
    case dropped([DroppedItem])
    /// What a drop comes to once Vortex's own files are read and the content is hashed, both off the main actor.
    case dropPrepared(ClipboardCopy)
    case imageSaved(ClipboardItem)
    case itemTapped(ClipboardItem.ID)
    case copiedAgain(ClipboardItem.ID)
    case pinTapped(ClipboardItem.ID)
    case deleteTapped(ClipboardItem.ID)
    case clearTapped
    case revealTapped(ClipboardItem.ID)
    case showInFinderTapped(ClipboardItem.ID)
    /// The tab became visible: the window opened on it, or the user switched to it.
    case tabShown
    case unavailableChecked(Set<ClipboardItem.ID>)
    case copiedMarkElapsed
    case settingsShown
    case runningAppsLoaded([AppInfo])
    case ignoreAppTapped(AppInfo)
    case chooseAppTapped
    case appChosen(AppInfo?)
    case stopIgnoringAppTapped(bundleID: String)
    /// "Turn on" in the settings row of a permission that is off: the shell's page.
    case turnOnTapped(Permission)
    /// "Restart Vortex" in the row of a permission that works after a relaunch.
    case restartTapped
  }

  @Dependency(\.appsClient) var apps
  @Dependency(\.continuousClock) var clock
  @Dependency(\.database) var database
  @Dependency(\.databaseIsOnDisk) var databaseIsOnDisk
  @Dependency(\.date.now) var now
  @Dependency(\.fileClient) var files
  @Dependency(\.pasteboardClient) var pasteboard
  @Dependency(\.permissionPage) var permissionPage
  @Dependency(\.permissionsClient) var permissions
  @Dependency(\.systemClient) var system
  @Dependency(\.uuid) var uuid

  private enum CancelID {
    case load
    case watch
    case copiedMark
    case wholeText
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .start:
        guard !state.isLoaded else { return watch(state) }
        // `databaseIsOnDisk` is read in the effect: reading it opens the database, which stays off the main thread.
        return .run { [files] send in
          try await database.migrate(ClipboardItem.migrator)
          var (items, savedIDs) = try await database.read { db in
            (try ClipboardItem.fetchAllReadable(db), try ClipboardItem.savedIDs(db))
          }
          try await ClipboardItem.complete(&items, files: files, in: database)
          // Image folders whose rows are gone, after a crash or a failed save. Before watching starts,
          // so a new image is never taken for one of them. Not while the database is only in memory: its file didn't
          // open, and the pictures are then all that is left.
          if databaseIsOnDisk {
            for folder in await files.contents(ClipboardItem.imagesFolder) where !savedIDs.contains(folder.lastPathComponent) {
              await files.remove(folder)
            }
          }
          await send(.loaded(IdentifiedArray(items, uniquingIDsWith: { first, _ in first })))
        } catch: { error, send in
          logger.error("Loading the clipboard history failed: \(error, privacy: .public)")
          await send(.loadFailed)
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)

      case .stop:
        return .merge(.cancel(id: CancelID.load), .cancel(id: CancelID.watch))

      case let .loaded(items):
        state.items = items
        state.isLoaded = true
        return watch(state)

      case .loadFailed:
        state.isLoaded = true
        state.savesToDisk = false
        return watch(state)

      case let .written(previews):
        state.isWriting = false
        for (id, preview) in previews {
          // A text that turned secret meanwhile has its row deleted next: memory keeps it whole.
          guard let item = state.items[id: id], !item.isConcealed, !item.isTruncated else { continue }
          state.items[id: id]?.content = .text(preview)
          state.items[id: id]?.isTruncated = true
        }
        return .none

      case let .itemHovered(id):
        guard state.items[id: id]?.isTruncated == true, state.wholeText?.id != id else { return .none }
        return .run { send in
          let text = try await database.read { db in try ClipboardItem.wholeText(of: id, db) }
          await send(.wholeTextRead(id, text))
        } catch: { error, _ in
          logger.error("Reading the whole text of an item failed: \(error, privacy: .public)")
        }
        .cancellable(id: CancelID.wholeText, cancelInFlight: true)

      case let .wholeTextRead(id, text):
        guard state.items[id: id]?.isTruncated == true else { return .none }
        state.wholeText = WholeText(id: id, text: text)
        return .none

      case let .copied(copied):
        let copy = copied.copy
        let ignored = Set(state.settings.ignoredApps.map(\.bundleID))
        if !copy.frontApps.isDisjoint(with: ignored) || copy.source.map({ ignored.contains($0.bundleID) }) == true {
          return .none
        }
        if let existing = state.items.first(where: { $0.fingerprint == copied.fingerprint }) {
          // The copy holds the whole text, which memory needs again if the item turns secret.
          let wholeText: String? = if case let .text(text) = copy.content { text } else { nil }
          bump(existing.id, source: copy.source, isConcealed: copy.isConcealed, wholeText: wholeText, &state)
          return .none
        }
        var item = ClipboardItem(
          id: uuid(),
          content: .text(""),
          source: copy.source,
          copiedAt: now,
          isConcealed: copy.isConcealed,
          fingerprint: copied.fingerprint,
          byteSize: copied.byteSize
        )
        switch copy.content {
        case let .text(text):
          item.content = .text(text)
        case let .link(url):
          item.content = .link(url)
        case let .files(urls):
          item.content = .files(urls)
        case let .image(png):
          // Secrets never reach the disk, and an image needs a file for its card.
          guard !copy.isConcealed else { return .none }
          // The card shows the image from its file, so the item appears once the file is written.
          item.content = .image(fileName: Self.imageFileName(copiedAt: now))
          return .run { [item, files] send in
            guard let url = item.imageURL else { return }
            try await files.write(png, url)
            await send(.imageSaved(item))
          } catch: { error, _ in
            logger.error("Saving a copied image failed: \(error, privacy: .public)")
          }
        }
        return insert(item, &state)

      case let .imageSaved(item):
        // The same image may have been copied again while the file was written.
        if let existing = state.items.first(where: { $0.fingerprint == item.fingerprint }) {
          bump(existing.id, source: item.source, isConcealed: item.isConcealed, &state)
          return removeFolders([item.imageURL?.deletingLastPathComponent()].compactMap { $0 })
        }
        return insert(item, &state)

      case let .dropped(items):
        // Before the saved history is read there is nothing to add to: the load would replace it.
        guard state.isLoaded else { return .none }
        return .run { [files] send in
          guard let content = await Self.copiedContent(of: items, files: files) else { return }
          // Hashing an image is not for the main thread, so it happens here, together with the reading.
          await send(.dropPrepared(ClipboardCopy(PasteboardCopy(content: content))))
        }

      case let .dropPrepared(copied):
        if let existing = state.items.first(where: { $0.fingerprint == copied.fingerprint }) {
          // Files dropped just now exist, whatever the last check of the history found.
          if case .files = existing.content { state.unavailable.remove(existing.id) }
          // The history already holds it: copying that item again keeps its marks, so a secret stays one.
          if !state.unavailable.contains(existing.id) { return .send(.itemTapped(existing.id)) }
        }
        let content = copied.copy.content
        return .run { send in
          await pasteboard.write(content, false, nil)
          // The pasteboard watcher skips Vortex's own writes, so the drop joins the history here.
          await send(.copied(copied))
        }

      case let .itemTapped(id):
        guard let item = state.items[id: id], !state.unavailable.contains(id) else { return .none }
        let wholeText = state.wholeText?.id == id ? state.wholeText?.text : nil
        return .run { [files] send in
          let content: PasteboardContent
          switch item.content {
          case let .text(text):
            if !item.isTruncated {
              content = .text(text)
            } else if let wholeText {
              content = .text(wholeText)
            } else {
              // Memory holds only the start of a long text: the whole of it is read here, off the main thread.
              content = .text(try await database.read { db in try ClipboardItem.wholeText(of: id, db) })
            }
          case let .link(url): content = .link(url)
          case let .files(urls): content = .files(urls)
          case .image: content = .image(try await files.read(item.imageURL!))
          }
          await pasteboard.write(content, item.isConcealed, item.source)
          await send(.copiedAgain(id))
        } catch: { error, _ in
          logger.error("Copying an item again failed: \(error, privacy: .public)")
        }

      case let .copiedAgain(id):
        guard let item = state.items[id: id] else { return .none }
        state.justCopied = id
        bump(id, source: item.source, isConcealed: item.isConcealed, &state)
        return .run { send in
          try await clock.sleep(for: .seconds(1.2))
          await send(.copiedMarkElapsed)
        }
        .cancellable(id: CancelID.copiedMark, cancelInFlight: true)

      case let .pinTapped(id):
        guard var item = state.items.remove(id: id) else { return .none }
        item.isPinned.toggle()
        state.items.insert(item, at: state.items.index(forNew: item))
        save(item.isConcealed ? [] : [.update(item)], &state)
        return .none

      case let .deleteTapped(id):
        guard let item = state.items.remove(id: id) else { return .none }
        return remove([item], &state)

      case .clearTapped:
        let cleared = state.items.filter { !$0.isPinned }
        state.items.removeAll { !$0.isPinned }
        return remove(Array(cleared), &state)

      case let .revealTapped(id):
        if state.revealed.remove(id) == nil {
          state.revealed.insert(id)
        }
        return .none

      case let .showInFinderTapped(id):
        guard let urls = state.items[id: id]?.fileURLs, !urls.isEmpty else { return .none }
        return .run { [files] _ in await files.revealInFinder(urls) }

      case .tabShown:
        state.revealed = []
        let checks = state.items.filter { !$0.fileURLs.isEmpty }.map { ($0.id, $0.fileURLs) }
        guard !checks.isEmpty else { return .none }
        return .run { [files] send in
          var missing = Set<ClipboardItem.ID>()
          for (id, urls) in checks {
            for url in urls where await files.info(url) == nil {
              missing.insert(id)
              break
            }
          }
          await send(.unavailableChecked(missing))
        }

      case let .unavailableChecked(missing):
        state.unavailable = missing
        return .none

      case .copiedMarkElapsed:
        state.justCopied = nil
        return .none

      case .settingsShown:
        return .merge(
          .run { send in await send(.runningAppsLoaded(apps.running())) },
          // The permission row shows what macOS says now.
          .run { _ in await permissions.refresh() }
        )

      case let .turnOnTapped(permission):
        return .run { _ in await permissionPage.open(permission) }

      case .restartTapped:
        return .run { _ in await system.relaunch() }

      case let .runningAppsLoaded(apps):
        state.runningApps = apps
        return .none

      case let .ignoreAppTapped(app):
        state.$settings.withLock { settings in
          guard !settings.ignoredApps.contains(where: { $0.bundleID == app.bundleID }) else { return }
          settings.ignoredApps.append(app)
          settings.ignoredApps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return .none

      case .chooseAppTapped:
        return .run { send in await send(.appChosen(apps.choose())) }

      case let .appChosen(app):
        guard let app else { return .none }
        return .send(.ignoreAppTapped(app))

      case let .stopIgnoringAppTapped(bundleID):
        state.$settings.withLock { $0.ignoredApps.removeAll { $0.bundleID == bundleID } }
        return .none
      }
    }
    // Whatever an action queued goes to the database once the batch being written is in, so writes keep their order.
    Reduce { state, _ in
      writeQueued(&state)
    }
  }

  /// Pinned first, then newest first.
  static func displayOrder(_ lhs: ClipboardItem, _ rhs: ClipboardItem) -> Bool {
    lhs.isPinned != rhs.isPinned ? lhs.isPinned : lhs.copiedAt > rhs.copiedAt
  }

  /// "Image 2026-10-04 at 14.03.12.png": the name the image has when dragged into another app, in the words macOS gives
  /// such an image in the app's language; the date and time read the same in every language.
  static func imageFileName(copiedAt date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    let day = formatter.string(from: date)
    formatter.dateFormat = "HH.mm.ss"
    let time = formatter.string(from: date)
    let name = String(localized: "Image \(day) at \(time)", bundle: .module, comment: "File name of a copied image: the date and the time")
    return "\(name).png"
  }

  /// Whether a file lives in Vortex's own data folder: the history's image files, the shelf's copies. Such a file goes
  /// away with its owner.
  static func isOwnFile(_ url: URL) -> Bool {
    url.standardizedFileURL.path.hasPrefix(DataFolder.url.standardizedFileURL.path + "/")
  }

  /// Whether a dropped file goes away soon: one of Vortex's own with its owner, a temporary one (a screenshot dragged
  /// from its thumbnail) once the drag is over.
  static func isFleeting(_ url: URL) -> Bool {
    isOwnFile(url) || DroppedItem.isTemporary(url)
  }

  /// What a drop that may hold fleeting files (Vortex's own, temporary ones) copies, as `copiedContent(of:)` decides it.
  /// A reference to such a file would not last, so a fleeting PNG counts as the image it is (an image row dragged back
  /// reads as the very image it came from, a screenshot from its thumbnail as the screenshot) and any other fleeting file
  /// is left out. Lasting files win, and then no fleeting file is read; otherwise fleeting PNGs are read in drop order,
  /// only until one of them is what the drop copies.
  static func copiedContent(of items: [DroppedItem], files: FileClient) async -> PasteboardContent? {
    let others = items.filter { item in
      if case let .file(url) = item { !isFleeting(url) } else { true }
    }
    if others.contains(where: { if case .file = $0 { true } else { false } }) {
      return copiedContent(of: others)
    }
    for item in items {
      if case let .file(url) = item {
        // A fleeting one: lasting files are handled above.
        guard url.pathExtension.lowercased() == "png", let png = try? await files.read(url) else { continue }
        return .image(png)
      }
      if let content = copiedContent(of: [item]) { return content }
    }
    return nil
  }

  /// What dropping things on the clipboard copies: every dropped file together, otherwise the first image, link or
  /// text. Only PNG images: the history keeps images as PNG files.
  static func copiedContent(of items: [DroppedItem]) -> PasteboardContent? {
    let files = items.compactMap { item -> URL? in
      if case let .file(url) = item { url } else { nil }
    }
    if !files.isEmpty { return .files(files) }
    for item in items {
      switch item {
      case let .image(data, fileExtension) where fileExtension.lowercased() == "png":
        return .image(data)
      case .image, .file:
        continue
      case let .link(url):
        return .link(url)
      case let .text(text):
        return .text(text)
      }
    }
    return nil
  }

  /// Records copies, except while Paste from Other Apps reads `notGranted`: macOS then enforces pasteboard
  /// privacy and Vortex isn't allowed, so reading a copy could make macOS alert. The pasteboard isn't read at all then,
  /// nothing is recorded, and watching starts again when the status changes.
  private func watch(_ state: State) -> Effect<Action> {
    .run { [statuses = state.$permissionStatuses] send in
      let (changes, continuation) = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(1))
      let subscription = statuses.publisher
        .map(Self.mayReadPasteboard)
        .removeDuplicates()
        .sink { continuation.yield($0) }
      defer { subscription.cancel() }
      var copying: Task<Void, Never>?
      defer { copying?.cancel() }
      for await mayRead in changes {
        copying?.cancel()
        copying = nil
        guard mayRead else { continue }
        copying = Task {
          for await copy in pasteboard.copies() {
            // Hashing an image is not for the main thread, so it happens here.
            await send(.copied(ClipboardCopy(copy)))
          }
        }
      }
    }
    .cancellable(id: CancelID.watch, cancelInFlight: true)
  }

  /// The pasteboard may be read: Paste from Other Apps isn't off (granted, not needed, or not read yet).
  static func mayReadPasteboard(_ statuses: [Permission: PermissionStatus]) -> Bool {
    statuses[.pasteboard] != .notGranted
  }

  /// Adds a new item where it belongs, on top of the unpinned ones, and drops the oldest unpinned ones beyond the
  /// limit. No sort: the history stays in `displayOrder` as it is.
  private func insert(_ item: ClipboardItem, _ state: inout State) -> Effect<Action> {
    state.items.insert(item, at: state.items.index(forNew: item))
    save(item.isConcealed ? [] : [.insert(item)], &state)
    let pinned = state.items.prefix { $0.isPinned }.count
    let dropped = Array(state.items.dropFirst(pinned + Self.historyLimit))
    for item in dropped {
      state.items.remove(id: item.id)
    }
    return remove(dropped, &state)
  }

  /// Moves an item copied again to the top of its group. A secret stays one: copied again from an app that does not
  /// mark it, such as an editor it was pasted into, it is still the content the first app marked. An item that turns
  /// secret loses its row at once, and memory keeps its whole text again (`wholeText`, from the copy).
  private func bump(
    _ id: ClipboardItem.ID,
    source: AppInfo?,
    isConcealed: Bool,
    wholeText: String? = nil,
    _ state: inout State
  ) {
    guard var item = state.items.remove(id: id) else { return }
    let turnsSecret = isConcealed && !item.isConcealed
    item.copiedAt = now
    item.source = source
    if turnsSecret {
      item.isConcealed = true
      if item.isTruncated, let wholeText {
        item.content = .text(wholeText)
        item.isTruncated = false
      }
    }
    state.items.insert(item, at: state.items.index(forNew: item))
    if turnsSecret {
      // Its image file, if any, stays until the item goes.
      save([.delete([id], folders: [])], &state)
    } else if !item.isConcealed {
      save([.update(item)], &state)
    }
  }

  /// Items that left the history: forgets them, deletes their rows, then their image folders; referenced files are
  /// never touched. In a session that keeps the history in memory only, just the image folders go.
  private func remove(_ items: [ClipboardItem], _ state: inout State) -> Effect<Action> {
    guard !items.isEmpty else { return .none }
    let ids = Set(items.map(\.id))
    state.unavailable.subtract(ids)
    state.revealed.subtract(ids)
    if let wholeText = state.wholeText, ids.contains(wholeText.id) {
      state.wholeText = nil
    }
    let folders = items.compactMap { $0.imageURL?.deletingLastPathComponent() }
    guard state.isLoaded, state.savesToDisk else { return removeFolders(folders) }
    // A secret has no row.
    save([.delete(items.filter { !$0.isConcealed }.map(\.id), folders: folders)], &state)
    return .none
  }

  /// Deletes image folders now: images that never had a row.
  private func removeFolders(_ folders: [URL]) -> Effect<Action> {
    guard !folders.isEmpty else { return .none }
    return .run { [files] _ in
      for folder in folders {
        await files.remove(folder)
      }
    }
  }

  /// Queues changes for the database, in the order they are made (`writeQueued` writes them). Never before the saved
  /// history has been read, and never in a session that keeps the history in memory only.
  private func save(_ writes: [HistoryWrite], _ state: inout State) {
    guard state.isLoaded, state.savesToDisk, !writes.isEmpty else { return }
    state.queuedWrites += writes
  }

  /// Writes the queued changes as one batch, unless a batch is being written: its `.written` comes first, and then
  /// this writes the rest. One batch at a time is what keeps the order: an insert followed by a delete of the same
  /// item never leaves its row behind. Image folders go once their rows are gone.
  private func writeQueued(_ state: inout State) -> Effect<Action> {
    guard !state.isWriting, !state.queuedWrites.isEmpty else { return .none }
    let batch = state.queuedWrites
    state.queuedWrites = []
    state.isWriting = true
    return .run { [files] send in
      var previews: [ClipboardItem.ID: String] = [:]
      do {
        let (written, folders) = try await database.write { db in HistoryWrite.apply(batch, db) }
        previews = written
        for folder in folders {
          await files.remove(folder)
        }
      } catch {
        logger.error("Saving the clipboard history failed: \(error, privacy: .public)")
      }
      await send(.written(previews: previews))
    }
  }
}

extension IdentifiedArray where Element == ClipboardItem {
  /// Where an item goes so the history stays in `displayOrder`: after every item that comes before it. A binary search,
  /// as a copy must not cost a sort of the whole history.
  func index(forNew item: ClipboardItem) -> Int {
    var low = startIndex
    var high = endIndex
    while low < high {
      let middle = (low + high) / 2
      if ClipboardFeature.displayOrder(self[middle], item) {
        low = middle + 1
      } else {
        high = middle
      }
    }
    return low
  }
}

private let logger = Logger(subsystem: "io.github.ortexisartem.vortex", category: "clipboard")
