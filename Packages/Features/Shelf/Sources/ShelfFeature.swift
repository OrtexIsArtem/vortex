import ComposableArchitecture
import Foundation
import GRDB
import os
import VortexCore
import VortexPlatform

/// A place for files the user puts aside to take somewhere else: dragged in, dropped on the menu bar icon, sent
/// from the terminal or found in the watched folder; dragged out into any app as many times as needed.
/// Clears itself after 24 hours.
@Reducer
public struct ShelfFeature: Sendable {
  public static let id: FeatureID = "shelf"
  /// Unpinned items leave the shelf this long after they were added.
  static let lifetime: TimeInterval = 24 * 60 * 60
  static let expiryCheckInterval: Duration = .seconds(600)
  /// A file in the watched folder counts as written once its size has stayed the same for two checks this far apart.
  static let settleInterval: Duration = .seconds(1)

  @ObservableState
  public struct State: Equatable {
    /// Newest first.
    public var items: IdentifiedArrayOf<ShelfItem> = []
    var isLoaded = false
    /// False when the saved shelf could not be read: this session keeps it in memory only, so nothing on disk is
    /// overwritten.
    var savesToDisk = true
    var isRunning = false
    /// What arrived before the shelf was loaded; added right after, so nothing overwrites the saved shelf.
    var pending: [Arrival] = []
    /// Files in the watched folders that are still being written.
    var waitingFiles: Set<URL> = []
    /// A path the user asked to watch that does not exist.
    var pathNotFound: String?
    var selection: Set<ShelfItem.ID> = []
    /// Where a shift-click selection starts.
    var selectionAnchor: ShelfItem.ID?
    /// Items that arrived by themselves (menu bar icon, terminal, watched folder): marked until the user leaves the tab.
    var fresh: Set<ShelfItem.ID> = []
    /// Size and kind of file items.
    var info: [ShelfItem.ID: FileInfo] = [:]
    /// Items whose file is gone.
    var unavailable: Set<ShelfItem.ID> = []
    /// Grows by one for every arrival that should flash the notch.
    var flashes = 0
    /// The color of the latest flash: by the number of new files, see `ShelfSettings.flashColors`.
    var flashColor = ColorValue.white
    @Shared(.notchIndicators) var indicators
    @Shared(.shelfSettings) var settings

    public init() {}

    /// The tray and the number of items in the closed notch. With an empty shelf it shows no ears, but can still
    /// flash the notch (Test in settings).
    var indicator: NotchIndicator? {
      guard isRunning else { return nil }
      return NotchIndicator(
        leading: items.isEmpty ? [] : [.symbol("tray.full")],
        trailing: items.isEmpty ? [] : [.text("\(items.count)")],
        flash: flashes,
        flashColor: flashColor
      )
    }

    /// What dragging an item carries: the whole selection if the item is in it, otherwise the item alone.
    func dragItems(startingAt id: ShelfItem.ID) -> [DragItem] {
      let ids = selection.contains(id) ? items.ids.filter(selection.contains) : [id]
      return ids.compactMap { items[id: $0] }.filter { !unavailable.contains($0.id) }.map(\.dragItem)
    }

    /// Things put on the shelf together, by the user (dropped on the tab) or by themselves.
    public struct Arrival: Equatable, Sendable {
      var items: [DroppedItem]
      var isFresh: Bool
    }

    /// Files of the selected items that are still there.
    var selectedFileURLs: [URL] {
      items.filter { selection.contains($0.id) && !unavailable.contains($0.id) }.compactMap(\.fileURL)
    }
  }

  public enum Action: Equatable, Sendable {
    case start
    case stop
    case loaded([ShelfItem])
    case loadFailed
    case dropped([DroppedItem])
    case filesReceived([URL])
    case copySaved(ShelfItem, isFresh: Bool)
    case expiryCheckDue
    case infoLoaded(found: [ShelfItem.ID: FileInfo], missing: Set<ShelfItem.ID>)
    case tabShown
    case tabHidden
    case itemClicked(ShelfItem.ID, DragSourceClick)
    case backgroundClicked
    case selectAllPressed
    case quickLookPressed
    case removeSelectedPressed
    case quickLookTapped(ShelfItem.ID)
    case showInFinderTapped(ShelfItem.ID)
    case pinTapped(ShelfItem.ID)
    case removeTapped(ShelfItem.ID)
    case clearTapped
    case watchedFileChanged(URL)
    case watchedFileWritten(URL)
    case watchedFileGone(URL)
    case chooseFolderTapped
    case folderChosen(URL?)
    /// A folder, an example file or a pattern like `…/last_builds/*.aab`, typed or pasted by the user.
    case watchPathSubmitted(String)
    /// What is at the submitted path: a folder, a file (or a pattern in an existing folder), or nothing.
    case watchPathChecked(String, isDirectory: Bool?)
    case stopWatchingTapped(URL)
    case extensionsChanged(URL, String)
    case flashColorChanged(index: Int, ColorValue)
    case flashColorAdded
    case lastFlashColorRemoved
    case flashColorsReset
    /// Plays the flashes for the first, second… new file three seconds later, so the window can be closed first.
    case testFlashTapped
    case testFlash(newFiles: Int)
  }

  @Dependency(\.continuousClock) var clock
  @Dependency(\.database) var database
  @Dependency(\.databaseIsOnDisk) var databaseIsOnDisk
  @Dependency(\.date.now) var now
  @Dependency(\.fileClient) var files
  @Dependency(\.quickLookClient) var quickLook
  @Dependency(\.uuid) var uuid

  private enum CancelID: Hashable {
    case load
    case expiry
    case save
    case watch
    case wait(URL)
    case testFlash
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .start:
        state.isRunning = true
        guard state.isLoaded else {
          return .run { [files, databaseIsOnDisk] send in
            try await database.migrate(ShelfItem.migrator)
            let (items, savedIDs) = try await database.read { db in
              (try ShelfItem.fetchAllReadable(db), try ShelfItem.savedIDs(db))
            }
            // Copies whose rows are gone, after a crash or a failed save; before anything new is added. Not while the
            // database is only in memory: its file didn't open, and the copies are then all that is left.
            if databaseIsOnDisk {
              for folder in await files.contents(ShelfItem.copiesFolder) where !savedIDs.contains(folder.lastPathComponent) {
                await files.remove(folder)
              }
            }
            await send(.loaded(items))
          } catch: { error, send in
            logger.error("Loading the shelf failed: \(error, privacy: .public)")
            await send(.loadFailed)
          }
          .cancellable(id: CancelID.load, cancelInFlight: true)
        }
        return .merge(removeExpired(&state), checkExpiry(), watch(state))

      case .stop:
        state.isRunning = false
        return .merge(.cancel(id: CancelID.load), .cancel(id: CancelID.expiry), stopWatching(&state))

      case let .loaded(items):
        state.items = IdentifiedArray(items, uniquingIDsWith: { first, _ in first })
        state.isLoaded = true
        let pending = state.pending
        state.pending = []
        return .merge(
          [loadInfo(for: state.items.elements), removeExpired(&state)]
            + pending.map { add($0.items, isFresh: $0.isFresh, &state) }
            + [checkExpiry(), watch(state)]
        )

      case .loadFailed:
        state.savesToDisk = false
        return .send(.loaded([]))

      case let .dropped(dropped):
        guard state.isLoaded else {
          state.pending.append(State.Arrival(items: dropped, isFresh: false))
          return .none
        }
        return add(dropped, isFresh: false, &state)

      case let .filesReceived(urls):
        guard state.isLoaded else {
          state.pending.append(State.Arrival(items: urls.map(DroppedItem.file), isFresh: true))
          return .none
        }
        return add(urls.map(DroppedItem.file), isFresh: true, &state)

      case let .copySaved(item, isFresh):
        state.items.insert(item, at: 0)
        if isFresh { arrived([item.id], &state) }
        return .merge(loadInfo(for: [item]), save(state))

      case .expiryCheckDue:
        return removeExpired(&state)

      case let .infoLoaded(found, missing):
        state.info.merge(found) { _, new in new }
        state.unavailable.subtract(found.keys)
        state.unavailable.formUnion(missing)
        return .none

      case .tabShown:
        return loadInfo(for: state.items.elements)

      case .tabHidden:
        state.fresh = []
        return .run { _ in await quickLook.close() }

      case let .itemClicked(id, click):
        guard let item = state.items[id: id] else { return .none }
        if click.count == 2 {
          guard !state.unavailable.contains(id), let url = item.fileURL ?? item.linkURL else { return .none }
          return .run { [files] _ in await files.open(url) }
        }
        if click.modifiers.contains(.command) {
          if state.selection.remove(id) == nil { state.selection.insert(id) }
          state.selectionAnchor = id
        } else if click.modifiers.contains(.shift), let anchor = state.selectionAnchor,
                  let from = state.items.index(id: anchor), let to = state.items.index(id: id) {
          state.selection = Set(state.items[min(from, to)...max(from, to)].map(\.id))
        } else {
          state.selection = [id]
          state.selectionAnchor = id
        }
        return .none

      case .backgroundClicked:
        state.selection = []
        state.selectionAnchor = nil
        return .none

      case .selectAllPressed:
        state.selection = Set(state.items.ids)
        return .none

      case .quickLookPressed:
        let urls = state.selectedFileURLs
        guard !urls.isEmpty else { return .none }
        return .run { _ in await quickLook.toggle(urls) }

      case let .quickLookTapped(id):
        if !state.selection.contains(id) {
          state.selection = [id]
          state.selectionAnchor = id
        }
        return .send(.quickLookPressed)

      case .removeSelectedPressed:
        guard !state.selection.isEmpty else { return .none }
        let removed = remove(state.selection, &state)
        return .merge(deleteCopies(of: removed), save(state))

      case let .showInFinderTapped(id):
        let urls = state.selection.contains(id) ? state.selectedFileURLs : state.items[id: id]?.fileURL.map { [$0] } ?? []
        guard !urls.isEmpty else { return .none }
        return .run { [files] _ in await files.revealInFinder(urls) }

      case let .pinTapped(id):
        state.items[id: id]?.isPinned.toggle()
        return save(state)

      case let .removeTapped(id):
        let removed = remove([id], &state)
        return .merge(deleteCopies(of: removed), save(state))

      case .clearTapped:
        let removed = remove(Set(state.items.filter { !$0.isPinned }.ids), &state)
        return .merge(deleteCopies(of: removed), save(state))

      case let .watchedFileChanged(url):
        guard state.isRunning, state.settings.takes(url) else { return .none }
        // Every change starts the wait for that file over.
        state.waitingFiles.insert(url)
        return .run { [files, clock] send in
          let isWritten = await Self.waitUntilWritten(url, files: files, clock: clock)
          await send(isWritten ? .watchedFileWritten(url) : .watchedFileGone(url))
        }
        .cancellable(id: CancelID.wait(url), cancelInFlight: true)

      case let .watchedFileWritten(url):
        state.waitingFiles.remove(url)
        guard state.isRunning else { return .none }
        return add([.file(url)], isFresh: true, &state)

      case let .watchedFileGone(url):
        state.waitingFiles.remove(url)
        return .none

      case .chooseFolderTapped:
        return .run { [files] send in await send(.folderChosen(await files.chooseFolder())) }

      case let .folderChosen(folder):
        guard let folder else { return .none }
        return startWatching(ShelfSettings.WatchedFolder(folder: folder, extensions: ShelfSettings.defaultExtensions), &state)

      case let .watchPathSubmitted(text):
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        state.pathNotFound = nil
        let url = URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
        return .run { [files] send in
          if url.lastPathComponent.contains("*") {
            // A pattern such as `*.aab` names no file; its folder has to exist.
            let folder = await files.info(url.deletingLastPathComponent())
            await send(.watchPathChecked(trimmed, isDirectory: folder?.isDirectory == true ? false : nil))
          } else {
            await send(.watchPathChecked(trimmed, isDirectory: await files.info(url)?.isDirectory))
          }
        }

      case let .watchPathChecked(text, isDirectory):
        guard let isDirectory else {
          state.pathNotFound = text
          return .none
        }
        return startWatching(ShelfSettings.watchedFolder(forPath: text, isDirectory: isDirectory), &state)

      case let .stopWatchingTapped(folder):
        state.$settings.withLock { $0.watchedFolders.removeAll { $0.folder.path == folder.path } }
        return .merge(stopWatching(&state), watch(state))

      case let .flashColorChanged(index, color):
        state.$settings.withLock { settings in
          guard settings.flashColors.indices.contains(index) else { return }
          settings.flashColors[index] = color
        }
        return .none

      case .flashColorAdded:
        state.$settings.withLock { $0.flashColors.append($0.nextFlashColor) }
        return .none

      case .lastFlashColorRemoved:
        state.$settings.withLock { _ = $0.flashColors.popLast() }
        return .none

      case .flashColorsReset:
        state.$settings.withLock { $0.flashColors = ShelfSettings.defaultFlashColors }
        return .none

      case .testFlashTapped:
        let colors = state.settings.flashColors.count
        return .run { send in
          try await clock.sleep(for: .seconds(3))
          // Every color, then the white that follows the last one.
          for newFiles in 1...(colors + 1) {
            await send(.testFlash(newFiles: newFiles))
            try await clock.sleep(for: .seconds(1.8))
          }
        }
        .cancellable(id: CancelID.testFlash, cancelInFlight: true)

      case let .testFlash(newFiles):
        state.flashColor = state.settings.flashColor(forNewFiles: newFiles)
        state.flashes += 1
        return .none

      case let .extensionsChanged(folder, text):
        state.$settings.withLock { settings in
          guard let index = settings.watchedFolders.firstIndex(where: { $0.folder.path == folder.path }) else { return }
          settings.watchedFolders[index].extensions = ShelfSettings.extensions(from: text)
        }
        return .none
      }
    }
    .onChange(of: \.indicator) { _, indicator in
      Reduce { state, _ in
        state.$indicators.withLock { $0[Self.id] = indicator }
        return .none
      }
    }
  }

  /// Puts things on the shelf, newest first. Something already there moves to the front instead of being added again.
  private func add(_ dropped: [DroppedItem], isFresh: Bool, _ state: inout State) -> Effect<Action> {
    guard !dropped.isEmpty else { return .none }
    var added: [ShelfItem] = []
    var moved: [ShelfItem.ID] = []
    var copies: [Effect<Action>] = []
    var copiedNames: Set<String> = []
    func isKnown(_ matches: (ShelfItem) -> Bool) -> Bool {
      if let existing = state.items.first(where: matches) {
        moved.append(existing.id)
        return true
      }
      return added.contains(where: matches)
    }
    for dropped in dropped {
      let content: ShelfItem.Content
      switch dropped {
      case let .file(url):
        let url = url.standardizedFileURL
        if isKnown({ $0.fileURL == url }) { continue }
        guard url.path.hasPrefix(DataFolder.url.standardizedFileURL.path + "/") || DroppedItem.isTemporary(url) else {
          content = .file(url)
          break
        }
        // A file of Vortex's own, such as a clipboard image, goes away with its owner, and a temporary one, such as a
        // screenshot dragged from its thumbnail, once the drag is over: the shelf keeps a copy. The copy keeps only the
        // name, so the same file dropped again finds its copy by it, unless that copy's file is gone.
        let copy = ShelfItem.Content.copy(fileName: url.lastPathComponent)
        if isKnown({ $0.content == copy && !state.unavailable.contains($0.id) }) { continue }
        guard copiedNames.insert(url.lastPathComponent).inserted else { continue }
        let item = ShelfItem(id: uuid(), content: copy, addedAt: now)
        copies.append(saveCopy(item, isFresh: isFresh) { [files] destination in try await files.copy(url, destination) })
        continue
      case let .image(data, fileExtension):
        let name = Self.imageFileName(addedAt: now, fileExtension: fileExtension)
        let item = ShelfItem(id: uuid(), content: .copy(fileName: name), addedAt: now)
        copies.append(saveCopy(item, isFresh: isFresh) { [files] destination in try await files.write(data, destination) })
        continue
      case let .text(text):
        content = .text(text)
      case let .link(url):
        content = .link(url)
      }
      if isKnown({ $0.content == content }) { continue }
      added.append(ShelfItem(id: uuid(), content: content, addedAt: now))
    }

    var front = added
    for id in moved {
      guard var item = state.items.remove(id: id) else { continue }
      item.addedAt = now
      front.append(item)
    }
    state.items = IdentifiedArray(front + state.items.elements, uniquingIDsWith: { first, _ in first })
    if isFresh { arrived(added.map(\.id) + moved, &state) }
    return .merge([loadInfo(for: added), save(state)] + copies)
  }

  /// Marks things that came by themselves and flashes the notch once, in the color for the number of new files.
  private func arrived(_ ids: [ShelfItem.ID], _ state: inout State) {
    guard !ids.isEmpty else { return }
    state.fresh.formUnion(ids)
    state.flashColor = state.settings.flashColor(forNewFiles: state.fresh.count)
    state.flashes += 1
  }

  /// Writes the file of a copy item, then adds the item: its thumbnail needs the file.
  private func saveCopy(
    _ item: ShelfItem,
    isFresh: Bool,
    write: @escaping @Sendable (URL) async throws -> Void
  ) -> Effect<Action> {
    .run { send in
      guard let destination = item.fileURL else { return }
      try await write(destination)
      await send(.copySaved(item, isFresh: isFresh))
    } catch: { error, _ in
      logger.error("Keeping a copy on the shelf failed: \(error, privacy: .public)")
    }
  }

  /// Takes items off the shelf and returns them.
  private func remove(_ ids: Set<ShelfItem.ID>, _ state: inout State) -> [ShelfItem] {
    let removed = state.items.filter { ids.contains($0.id) }
    state.items.removeAll { ids.contains($0.id) }
    state.selection.subtract(ids)
    state.fresh.subtract(ids)
    state.unavailable.subtract(ids)
    for id in ids { state.info[id] = nil }
    if let anchor = state.selectionAnchor, ids.contains(anchor) { state.selectionAnchor = nil }
    return Array(removed)
  }

  /// Unpinned items older than a day leave the shelf.
  private func removeExpired(_ state: inout State) -> Effect<Action> {
    let limit = now.addingTimeInterval(-Self.lifetime)
    let removed = remove(Set(state.items.filter { !$0.isPinned && $0.addedAt < limit }.ids), &state)
    guard !removed.isEmpty else { return .none }
    return .merge(deleteCopies(of: removed), save(state))
  }

  /// Watches the folders from the settings; each change goes through `watchedFileChanged`.
  private func watch(_ state: State) -> Effect<Action> {
    let folders = state.settings.watchedFolders.map(\.folder)
    guard state.isRunning, state.isLoaded, !folders.isEmpty else {
      return .cancel(id: CancelID.watch)
    }
    return .run { [files] send in
      await withTaskGroup(of: Void.self) { group in
        for folder in folders {
          group.addTask {
            for await url in files.changes(folder) {
              await send(.watchedFileChanged(url))
            }
          }
        }
      }
    }
    .cancellable(id: CancelID.watch, cancelInFlight: true)
  }

  /// Adds a folder to watch, or takes the new types for a folder already watched, and restarts watching.
  private func startWatching(_ watched: ShelfSettings.WatchedFolder, _ state: inout State) -> Effect<Action> {
    state.pathNotFound = nil
    state.$settings.withLock { settings in
      if let index = settings.watchedFolders.firstIndex(where: { $0.folder == watched.folder }) {
        let types = settings.watchedFolders[index].extensions
        settings.watchedFolders[index].extensions = types.isEmpty ? [] : Array(Set(types + watched.extensions)).sorted()
      } else {
        settings.watchedFolders.append(watched)
      }
    }
    return .merge(stopWatching(&state), watch(state))
  }

  /// Stops watching the folders and every wait for a file in them.
  private func stopWatching(_ state: inout State) -> Effect<Action> {
    let waits = state.waitingFiles.map { Effect<Action>.cancel(id: CancelID.wait($0)) }
    state.waitingFiles = []
    return .merge([.cancel(id: CancelID.watch)] + waits)
  }

  /// True once the file's size stays the same for two checks `settleInterval` apart; false when it goes away,
  /// stays empty, or the wait is cancelled.
  static func waitUntilWritten(_ url: URL, files: FileClient, clock: any Clock<Duration>) async -> Bool {
    var lastSize: Int64?
    var steadyChecks = 0
    while true {
      do {
        try await clock.sleep(for: settleInterval)
      } catch {
        return false
      }
      guard let info = await files.info(url), !info.isDirectory, let size = info.size else { return false }
      if size == lastSize {
        // An empty file that stays empty is a placeholder, not a build.
        if size == 0 { return false }
        steadyChecks += 1
        if steadyChecks == 2 { return true }
      } else {
        steadyChecks = 0
      }
      lastSize = size
    }
  }

  private func checkExpiry() -> Effect<Action> {
    .run { send in
      for await _ in clock.timer(interval: Self.expiryCheckInterval) {
        await send(.expiryCheckDue)
      }
    }
    .cancellable(id: CancelID.expiry, cancelInFlight: true)
  }

  /// Looks up size and kind of the items' files; missing files mark their items unavailable.
  private func loadInfo(for items: [ShelfItem]) -> Effect<Action> {
    let files = items.compactMap { item in item.fileURL.map { (item.id, $0) } }
    guard !files.isEmpty else { return .none }
    return .run { [client = self.files] send in
      var found: [ShelfItem.ID: FileInfo] = [:]
      var missing = Set<ShelfItem.ID>()
      for (id, url) in files {
        if let info = await client.info(url) {
          found[id] = info
        } else {
          missing.insert(id)
        }
      }
      await send(.infoLoaded(found: found, missing: missing))
    }
  }

  /// Deletes the shelf's own copies; the user's files are never touched.
  private func deleteCopies(of items: [ShelfItem]) -> Effect<Action> {
    let folders = items.filter(\.isCopy).compactMap { $0.fileURL?.deletingLastPathComponent() }
    guard !folders.isEmpty else { return .none }
    return .run { [files] _ in
      for folder in folders {
        await files.remove(folder)
      }
    }
  }

  /// Writes the whole shelf; a newer save cancels an older one that has not finished. Never before the saved shelf
  /// has been read, which would overwrite it.
  private func save(_ state: State) -> Effect<Action> {
    guard state.isLoaded, state.savesToDisk else { return .none }
    let items = state.items.elements
    return .run { _ in
      try await database.write { db in try ShelfItem.save(items, in: db) }
    } catch: { error, _ in
      logger.error("Saving the shelf failed: \(error, privacy: .public)")
    }
    .cancellable(id: CancelID.save, cancelInFlight: true)
  }

  /// "Image 2026-10-04 at 14.03.12.png": the name an image dropped without a file gets.
  static func imageFileName(addedAt date: Date, fileExtension: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return "Image \(formatter.string(from: date)).\(fileExtension)"
  }
}

extension ShelfItem {
  var linkURL: URL? {
    if case let .link(url) = content { url } else { nil }
  }
}

private let logger = Logger(subsystem: "io.github.ortexisartem.vortex", category: "shelf")
