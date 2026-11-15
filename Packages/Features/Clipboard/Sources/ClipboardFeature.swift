import ComposableArchitecture
import Foundation
import GRDB
import os
import VortexCore
import VortexPlatform

/// History of what the user copies, kept for the time the user chooses (a month by default) with backstops on count
/// and size, plus pinned ones, saved across launches.
@Reducer
public struct ClipboardFeature: Sendable {
  /// Unpinned items kept at most, whatever their age; pinned ones come on top of these.
  static let maxItems = 10_000
  /// What unpinned items may take on disk, image files plus text; past it the oldest images go first.
  static let maxBytes = 1_000_000_000
  /// How long Clear or a shorter lifetime can be taken back.
  static let undoTime: Duration = .seconds(5)
  /// How often the history is checked against its lifetime while the feature is on.
  static let checkInterval: Duration = .seconds(3_600)
  /// Typing pauses this long before a search runs.
  static let searchDelay: Duration = .milliseconds(150)
  /// File items whose files are checked when the tab shows, newest first; others when their card comes on screen.
  static let filesCheckedOnShow = 100
  /// Rows on Home (`State.homeItems`), of which at most `homePinnedRows` pinned: the tab has the rest.
  static let homeRows = 20
  static let homePinnedRows = 10

  /// The whole text of a long item, whose start alone is in memory, read for a drag.
  struct WholeText: Equatable {
    var id: ClipboardItem.ID
    var text: String
  }

  /// Items taken out of the history that Undo can still put back, for `undoTime`: their rows and image files stay
  /// until then.
  struct PendingRemoval: Equatable {
    enum Reason: Equatable {
      case cleared
      /// A shorter lifetime was chosen; Undo brings the previous one back too.
      case lifetime(previous: HistoryLifetime)
    }

    var items: [ClipboardItem]
    var reason: Reason
    /// Those of them marked "Not found": the mark comes back with them.
    var unavailable: Set<ClipboardItem.ID> = []
  }

  @ObservableState
  public struct State: Equatable {
    /// Pinned items first, then the others; newest first in both groups (`displayOrder`).
    public var items: IdentifiedArrayOf<ClipboardItem> = []
    var isLoaded = false
    /// False when the saved history could not be read: this session keeps it in memory only, so nothing on disk is
    /// overwritten.
    var savesToDisk = true
    /// Changes not in the database yet, in the order they were made; those being written come first. A change leaves
    /// only once it has landed, or can never be written.
    var queuedWrites: [HistoryWrite] = []
    /// How many of `queuedWrites`, from the first, are being written now; 0 while none is.
    var writing = 0
    /// Attempts that failed in a row; each waits longer before the next (`retryPause`).
    var failedWrites = 0
    /// The last attempt failed: the next waits for `.retryWrites`.
    var waitsToRetry = false
    /// The whole text of the long item the pointer was last over, so it drags out in full.
    var wholeText: WholeText?
    /// The long item the pointer came over last: a read of any other's whole text, ending late, is left unused.
    var hoveredLongText: ClipboardItem.ID?
    /// Clear or a shorter lifetime, while Undo can take it back.
    var pendingRemoval: PendingRemoval?
    /// What the search field holds.
    var query = ""
    /// What the search found, pinned first, newest first; nil while nothing is searched.
    var searchResults: [ClipboardItem.ID]?
    /// The history kept in memory only changed: no `.written` will come, so the search runs again after this action.
    var searchIsBehind = false
    /// Items whose files were checked since the tab was last shown.
    var checkedFiles: Set<ClipboardItem.ID> = []
    /// Items whose files are gone.
    var unavailable: Set<ClipboardItem.ID> = []
    /// Concealed items the user is looking at; hidden again whenever the window opens.
    var revealed: Set<ClipboardItem.ID> = []
    /// The item just copied again, marked for a moment.
    var justCopied: ClipboardItem.ID?
    /// Running apps, offered when the user adds an app to ignore.
    var runningApps: [AppInfo] = []
    /// Images copied in this session that wait to be read for search, in the order they were saved.
    var imagesToRead: [ClipboardItem.ID] = []
    /// The image being read now: one at a time, so a burst of copies never starts Vision requests side by side.
    var readingImage: ClipboardItem.ID?
    @Shared(.clipboardSettings) var settings
    /// What macOS says about Paste from Other Apps, read by the shell: the settings row, and no recording while it
    /// reads `notGranted`.
    @SharedReader(.permissionStatuses) var permissionStatuses

    public init() {}

    /// An item of the history, or one set aside by Clear or a shorter time that Undo can still bring back: either way
    /// its row is still there, unless it is a secret.
    func itemOrSetAside(_ id: ClipboardItem.ID) -> ClipboardItem? {
      items[id: id] ?? pendingRemoval?.items.first { $0.id == id }
    }

    /// What the History row shows: every item, pinned ones too, and what they take on disk (a secret takes nothing).
    var historySize: (items: Int, bytes: Int) {
      (items.count, items.reduce(0) { $0 + $1.storedBytes })
    }

    /// A search is shown: the query has a word. The one test for it, whether the search runs, Clear hides or "Nothing
    /// found" may show; a query of spaces only is no search.
    var isSearching: Bool {
      !ClipboardFeature.searchWords(query).isEmpty
    }

    /// Home's rows, in the tab's order: at most `homePinnedRows` pinned items, newest first, then the newest unpinned
    /// ones, `homeRows` in all. Pinned items past those show only in the tab, even when Home has room for them. The
    /// history is pinned first, so a binary search finds where the unpinned start: nothing else of it is read.
    var homeItems: [ClipboardItem] {
      var low = items.startIndex
      var high = items.endIndex
      while low < high {
        let middle = (low + high) / 2
        if items[middle].isPinned {
          low = middle + 1
        } else {
          high = middle
        }
      }
      let pinned = items[..<low].prefix(ClipboardFeature.homePinnedRows)
      return Array(pinned) + Array(items[low...].prefix(ClipboardFeature.homeRows - pinned.count))
    }

    /// What the tab shows: the history, or what the search found in it, in the same order. Never a secret: it has no
    /// row to be found by, and one that turned secret after the search is left out here too.
    var shownItems: [ClipboardItem] {
      guard isSearching, let searchResults else { return items.elements }
      return searchResults.compactMap { items[id: $0] }.filter { !$0.isConcealed }
    }
  }

  public enum Action: Equatable, Sendable {
    case start
    case stop
    /// The saved history, read and ordered off the main thread.
    case loaded(IdentifiedArrayOf<ClipboardItem>)
    case loadFailed
    /// The first `done` queued changes are in the database, or left out as they can never be written; memory keeps
    /// the long texts they inserted by their start from now on. `failed`: the rest of the batch failed on the
    /// database's state, and is written again after a pause.
    case written(done: Int, previews: [ClipboardItem.ID: String], failed: Bool)
    /// The pause after a failed write is over.
    case retryWrites
    /// The pointer came over a card or a Home row: a long text's whole text is read, so it can be dragged out.
    case itemHovered(ClipboardItem.ID)
    case wholeTextRead(ClipboardItem.ID, String)
    case copied(ClipboardCopy)
    /// Something dropped on the clipboard on Home: copied, as if the user had copied it.
    case dropped([DroppedItem])
    /// What a drop comes to once Vortex's own files are read and the content is hashed, both off the main actor.
    case dropPrepared(ClipboardCopy)
    case imageSaved(ClipboardItem)
    /// The text read from a new image, in `ClipboardItem.imageSearchBody` form; nil when reading it failed.
    case imageRead(ClipboardItem.ID, body: String?)
    case itemTapped(ClipboardItem.ID)
    case copiedAgain(ClipboardItem.ID)
    case pinTapped(ClipboardItem.ID)
    case deleteTapped(ClipboardItem.ID)
    /// Clear, in the tab or in Settings: every unpinned item, with a moment to take it back.
    case clearTapped
    /// Keep history in Settings; a shorter time removes the older items, with a moment to take it back.
    case lifetimeChanged(HistoryLifetime)
    case undoTapped
    case undoExpired
    /// An hour has passed: items older than the lifetime go.
    case hourPassed
    case revealTapped(ClipboardItem.ID)
    case showInFinderTapped(ClipboardItem.ID)
    /// The tab became visible: the window opened on it, or the user switched to it.
    case tabShown
    /// A card came on screen: its files are checked, once per showing of the tab.
    case cardAppeared(ClipboardItem.ID)
    case filesChecked(checked: Set<ClipboardItem.ID>, missing: Set<ClipboardItem.ID>)
    case queryChanged(String)
    case searched([ClipboardItem.ID])
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
  @Dependency(\.textRecognitionClient) var textRecognition
  @Dependency(\.uuid) var uuid

  private enum CancelID {
    case load
    case watch
    case copiedMark
    case wholeText
    case undo
    case search
    case imageText
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .start:
        guard !state.isLoaded else { return watch(state) }
        // `databaseIsOnDisk` is read in the effect: reading it opens the database, which stays off the main thread.
        return .run { [files] send in
          let (items, savedIDs) = try await Self.loadHistory(database: database, files: files)
          // Image folders whose rows are gone, after a crash or a failed save. Before watching starts,
          // so a new image is never taken for one of them. Not while the database is only in memory: its file didn't
          // open, and the pictures are then all that is left.
          if databaseIsOnDisk {
            for folder in await files.contents(ClipboardItem.imagesFolder) where !savedIDs.contains(folder.lastPathComponent) {
              await files.remove(folder)
            }
          }
          await send(.loaded(items))
        } catch: { error, send in
          logger.error("Loading the clipboard history failed: \(error, privacy: .public)")
          await send(.loadFailed)
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)

      case .stop:
        // Images not read yet stay unread: found by their app only.
        state.imagesToRead = []
        state.readingImage = nil
        return .merge(.cancel(id: CancelID.load), .cancel(id: CancelID.watch), .cancel(id: CancelID.imageText))

      case let .loaded(items):
        state.items = items
        state.isLoaded = true
        // Read again (QA's seed) while Undo could still take something back: its rows were still there, so the
        // history holds those items again.
        state.pendingRemoval = nil
        return .merge(prune(&state), watch(state), searchAgain(state))

      case .loadFailed:
        state.isLoaded = true
        state.savesToDisk = false
        return watch(state)

      case let .written(done, previews, failed):
        state.queuedWrites.removeFirst(done)
        state.writing = 0
        for (id, preview) in previews {
          // A text that turned secret meanwhile has its row deleted next: memory keeps it whole.
          if let item = state.items[id: id], !item.isConcealed, !item.isTruncated {
            state.items[id: id]?.content = .text(preview)
            state.items[id: id]?.isTruncated = true
          }
          // Or it was cleared meanwhile, and may come back.
          if let index = state.pendingRemoval?.items.firstIndex(where: { $0.id == id && !$0.isConcealed }) {
            state.pendingRemoval?.items[index].content = .text(preview)
            state.pendingRemoval?.items[index].isTruncated = true
          }
        }
        // The history changed under the search: a copy, a pin, a removal.
        let searching = done > 0 ? searchAgain(state) : .none
        guard failed else {
          if state.failedWrites > 0 {
            state.failedWrites = 0
            return .merge(searching, .run { _ in logger.notice("Saving the clipboard history works again") })
          }
          return searching
        }
        // Never dropped: what failed stays first in the queue, and what is queued meanwhile follows it.
        state.failedWrites += 1
        state.waitsToRetry = true
        let pause = Self.retryPause(after: state.failedWrites)
        return .merge(
          searching,
          .run { send in
            try await clock.sleep(for: pause)
            await send(.retryWrites)
          }
        )

      case .retryWrites:
        state.waitsToRetry = false
        return .none

      case let .itemHovered(id):
        guard state.items[id: id]?.isTruncated == true else { return .none }
        state.hoveredLongText = id
        // Back over the card whose text is read: a read still running for another card goes unused.
        guard state.wholeText?.id != id else { return .cancel(id: CancelID.wholeText) }
        return .run { send in
          let text = try await database.read { db in try ClipboardItem.wholeText(of: id, db) }
          await send(.wholeTextRead(id, text))
        } catch: { error, _ in
          logger.error("Reading the whole text of an item failed: \(error, privacy: .public)")
        }
        .cancellable(id: CancelID.wholeText, cancelInFlight: true)

      case let .wholeTextRead(id, text):
        guard id == state.hoveredLongText, state.items[id: id]?.isTruncated == true else { return .none }
        state.wholeText = WholeText(id: id, text: text)
        return .none

      case let .copied(copied):
        let copy = copied.copy
        let ignored = Set(state.settings.ignoredApps.map(\.bundleID))
        if !copy.frontApps.isDisjoint(with: ignored) || copy.source.map({ ignored.contains($0.bundleID) }) == true {
          return .none
        }
        // The copy holds the whole text, which memory needs again if the item turns secret.
        let wholeText: String? = if case let .text(text) = copy.content { text } else { nil }
        if let existing = state.items.first(where: { $0.fingerprint == copied.fingerprint }) {
          return bump(existing.id, source: copy.source, isConcealed: copy.isConcealed, wholeText: wholeText, &state)
        }
        // Set aside by Clear or a shorter time and copied again within the 5 s: it comes back, as new. It keeps its one
        // row, so a quit never leaves two, and a secret copy deletes that row at once.
        if let setAside = state.pendingRemoval?.items.first(where: { $0.fingerprint == copied.fingerprint }) {
          bringBack([setAside], &state)
          return bump(setAside.id, source: copy.source, isConcealed: copy.isConcealed, wholeText: wholeText, &state)
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
          return .merge(
            bump(existing.id, source: item.source, isConcealed: item.isConcealed, &state),
            removeFolders([item.imageURL?.deletingLastPathComponent()].compactMap { $0 })
          )
        }
        let inserting = insert(item, &state)
        // A new image is read once for search, never a secret, and not in a session that keeps the history in memory
        // only: nothing would keep its text.
        guard state.isLoaded, state.savesToDisk, !item.isConcealed else { return inserting }
        state.imagesToRead.append(item.id)
        return .merge(inserting, readNextImage(&state))

      case let .imageRead(id, body):
        guard state.readingImage == id else { return .none }
        state.readingImage = nil
        // An item set aside by Clear still has its row, so Undo brings it back with its text; one that left for good,
        // or turned secret meanwhile, gets nothing.
        if let body, !body.isEmpty, let item = state.itemOrSetAside(id), !item.isConcealed {
          save([.text(id, body: body)], &state)
        }
        return readNextImage(&state)

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
        } else if let setAside = state.pendingRemoval?.items.first(where: { $0.fingerprint == copied.fingerprint }),
                  case .files = setAside.content {
          // Set aside by Clear or a shorter time, it comes back with the copy below: without the mark, for the same
          // reason.
          state.pendingRemoval?.unavailable.remove(setAside.id)
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
        return .merge(
          bump(id, source: item.source, isConcealed: item.isConcealed, &state),
          .run { send in
            try await clock.sleep(for: .seconds(1.2))
            await send(.copiedMarkElapsed)
          }
          .cancellable(id: CancelID.copiedMark, cancelInFlight: true)
        )

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
        // A removal waiting for Undo is final once another one is made.
        let settling = settlePendingRemoval(&state)
        let cleared = Set(state.items.lazy.filter { !$0.isPinned }.map(\.id))
        guard !cleared.isEmpty else { return settling }
        return .merge(settling, setAside(cleared, reason: .cleared, &state))

      case let .lifetimeChanged(lifetime):
        var previous = state.settings.historyLifetime
        guard lifetime != previous else { return .none }
        var settling = Effect<Action>.none
        if case let .lifetime(before) = state.pendingRemoval?.reason {
          // Within the 5 s of another time: that one is undone first, so the previous time again works as Undo, and
          // a new removal's Undo goes back to the choice before the first.
          putBack(&state)
          previous = before
        } else {
          // A pending Clear stands.
          settling = settlePendingRemoval(&state)
        }
        state.$settings.withLock { $0.historyLifetime = lifetime }
        let removed = Set(Self.removals(state.items, lifetime: lifetime, now: now))
        // Nothing removed: no Undo shows; the earlier timer, if any, then finds nothing to settle.
        guard !removed.isEmpty else { return settling }
        return .merge(settling, setAside(removed, reason: .lifetime(previous: previous), &state))

      case .undoTapped:
        guard let pending = state.pendingRemoval else { return .none }
        if case let .lifetime(previous) = pending.reason {
          state.$settings.withLock { $0.historyLifetime = previous }
        }
        putBack(&state)
        return .cancel(id: CancelID.undo)

      case .undoExpired:
        return settlePendingRemoval(&state)

      case .hourPassed:
        return prune(&state)

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
        state.query = ""
        state.searchResults = nil
        let pruning = prune(&state)
        // The files of the cards on top; any other card's when it comes on screen.
        state.checkedFiles = []
        let newest = state.items.lazy.filter { !$0.fileURLs.isEmpty }.prefix(Self.filesCheckedOnShow)
        return .merge(.cancel(id: CancelID.search), pruning, checkFiles(Array(newest), &state))

      case let .cardAppeared(id):
        guard let item = state.items[id: id] else { return .none }
        return checkFiles([item], &state)

      case let .filesChecked(checked, missing):
        state.unavailable.subtract(checked)
        state.unavailable.formUnion(missing.intersection(state.items.ids))
        return .none

      case let .queryChanged(query):
        state.query = query
        guard state.isSearching else {
          state.searchResults = nil
          return .cancel(id: CancelID.search)
        }
        return search(state, after: Self.searchDelay)

      case let .searched(ids):
        guard state.isSearching else { return .none }
        state.searchResults = ids
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
      guard state.searchIsBehind else { return writeQueued(&state) }
      state.searchIsBehind = false
      return .merge(writeQueued(&state), searchAgain(state))
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
  /// nothing is recorded, and watching starts again when the status changes. Every hour, old items go.
  private func watch(_ state: State) -> Effect<Action> {
    .merge(
      watchPasteboard(state),
      .run { send in
        for await _ in clock.timer(interval: Self.checkInterval) {
          await send(.hourPassed)
        }
      }
    )
    .cancellable(id: CancelID.watch, cancelInFlight: true)
  }

  private func watchPasteboard(_ state: State) -> Effect<Action> {
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
  }

  /// The pasteboard may be read: Paste from Other Apps isn't off (granted, not needed, or not read yet).
  static func mayReadPasteboard(_ statuses: [Permission: PermissionStatus]) -> Bool {
    statuses[.pasteboard] != .notGranted
  }

  /// The saved history, off the main thread: its tables made current, every readable row in `displayOrder`, rows from
  /// before `clipboard.v2` completed. Also every saved id, readable or not.
  static func loadHistory(
    database: any DatabaseWriter,
    files: FileClient
  ) async throws -> (items: IdentifiedArrayOf<ClipboardItem>, savedIDs: Set<String>) {
    try await database.migrate(ClipboardItem.migrator)
    var (items, savedIDs) = try await database.read { db in
      (try ClipboardItem.fetchAllReadable(db), try ClipboardItem.savedIDs(db))
    }
    try await ClipboardItem.complete(&items, files: files, in: database)
    return (IdentifiedArray(items, uniquingIDsWith: { first, _ in first }), savedIDs)
  }

  /// The words a query looks for, in `ClipboardItem.searchKey` form; an item matches when it holds every one.
  static func searchWords(_ query: String) -> [String] {
    ClipboardItem.searchKey(query).split(whereSeparator: \.isWhitespace).map(String.init)
  }

  /// Runs the search in SQL off the main thread, after `delay`, in place of one still running. A session that keeps the
  /// history in memory only has nothing in the database: it searches memory the same way, secrets left out.
  private func search(_ state: State, after delay: Duration? = nil) -> Effect<Action> {
    let words = Self.searchWords(state.query)
    let inMemory = state.savesToDisk ? nil : state.items.elements
    return .run { send in
      if let delay { try await clock.sleep(for: delay) }
      let ids: [ClipboardItem.ID]
      if let inMemory {
        ids = inMemory.filter { item in
          guard !item.isConcealed else { return false }
          let text = ClipboardItem.searchText(of: item.content, source: item.source)
          return words.allSatisfy { text.contains($0) }
        }
        .map(\.id)
      } else {
        ids = try await database.read { db in try ClipboardItem.search(words, db) }
      }
      await send(.searched(ids))
    } catch: { error, _ in
      guard !(error is CancellationError) else { return }
      logger.error("Searching the clipboard history failed: \(error, privacy: .public)")
    }
    .cancellable(id: CancelID.search, cancelInFlight: true)
  }

  /// The history changed while a search is shown: its results again, at once.
  private func searchAgain(_ state: State) -> Effect<Action> {
    state.isSearching ? search(state) : .none
  }

  /// Checks whether the files of these items are still there, each once per showing of the tab; missing ones are
  /// marked "Not found".
  private func checkFiles(_ items: [ClipboardItem], _ state: inout State) -> Effect<Action> {
    let checks = items
      .filter { !$0.fileURLs.isEmpty && !state.checkedFiles.contains($0.id) }
      .map { (id: $0.id, urls: $0.fileURLs) }
    guard !checks.isEmpty else { return .none }
    let checked = Set(checks.map(\.id))
    state.checkedFiles.formUnion(checked)
    return .run { [files] send in
      var missing = Set<ClipboardItem.ID>()
      for check in checks {
        for url in check.urls where await files.info(url) == nil {
          missing.insert(check.id)
          break
        }
      }
      await send(.filesChecked(checked: checked, missing: missing))
    }
  }

  /// What goes from the history: unpinned items last copied longer ago than `lifetime`; then the oldest unpinned ones
  /// beyond `maxItems`; then, while unpinned items take more than `maxBytes`, the oldest unpinned images, and once no
  /// image is left the oldest unpinned items of any kind. Pinned items never go. `items` is in `displayOrder`, so the
  /// unpinned ones come after the pinned, newest first.
  static func removals(_ items: IdentifiedArrayOf<ClipboardItem>, lifetime: HistoryLifetime, now: Date) -> [ClipboardItem.ID] {
    let unpinned = items.firstIndex { !$0.isPinned } ?? items.endIndex
    var end = items.endIndex
    if let days = lifetime.days {
      let oldest = now.addingTimeInterval(-Double(days) * 86_400)
      while end > unpinned, items[end - 1].copiedAt < oldest {
        end -= 1
      }
    }
    end = min(end, unpinned + maxItems)
    let removed = items[end...].map(\.id)
    var bytes = items[unpinned..<end].reduce(0) { $0 + $1.storedBytes }
    guard bytes > maxBytes else { return removed }
    var overSize = Set<Int>()
    for imagesOnly in [true, false] {
      for index in (unpinned..<end).reversed() where bytes > maxBytes && !overSize.contains(index) {
        // Images first; then any kind, though an item that takes nothing (a secret) frees nothing.
        guard imagesOnly ? items[index].isImage : items[index].storedBytes > 0 else { continue }
        overSize.insert(index)
        bytes -= items[index].storedBytes
      }
    }
    return removed + overSize.map { items[$0].id }
  }

  /// Removes for good what the lifetime and the backstops say must go (`removals`): from memory, then rows and image
  /// folders. After the load, after each copy, when the tab shows and every hour.
  private func prune(_ state: inout State) -> Effect<Action> {
    let ids = Set(Self.removals(state.items, lifetime: state.settings.historyLifetime, now: now))
    guard !ids.isEmpty else { return .none }
    let removed = state.items.filter { ids.contains($0.id) }
    state.items.removeAll { ids.contains($0.id) }
    return remove(removed.elements, &state)
  }

  /// Takes items out of the history for `undoTime`, as Clear or a shorter lifetime does: Undo puts them back, and their
  /// rows and image files stay until the time is over (`settlePendingRemoval`), so they are back at the next launch if
  /// Vortex quits meanwhile.
  private func setAside(
    _ ids: Set<ClipboardItem.ID>,
    reason: PendingRemoval.Reason,
    _ state: inout State
  ) -> Effect<Action> {
    let removed = state.items.filter { ids.contains($0.id) }
    state.items.removeAll { ids.contains($0.id) }
    let marks = state.unavailable.intersection(ids)
    forget(ids, &state)
    state.pendingRemoval = PendingRemoval(items: removed.elements, reason: reason, unavailable: marks)
    // The window closing doesn't stop it.
    return .run { send in
      try await clock.sleep(for: Self.undoTime)
      await send(.undoExpired)
    }
    .cancellable(id: CancelID.undo, cancelInFlight: true)
  }

  /// Puts items set aside back where they belong in the history, with their "Not found" marks, and takes them out of
  /// the pending removal; a Clear with nothing left to bring back is over. One item goes in by a binary search, as a
  /// copy must not cost a sort.
  private func bringBack(_ items: [ClipboardItem], _ state: inout State) {
    let ids = Set(items.map(\.id))
    if let marks = state.pendingRemoval?.unavailable.intersection(ids) {
      state.unavailable.formUnion(marks)
      state.pendingRemoval?.unavailable.subtract(marks)
    }
    state.pendingRemoval?.items.removeAll { ids.contains($0.id) }
    if items.count == 1, let item = items.first {
      state.items.insert(item, at: state.items.index(forNew: item))
    } else if !items.isEmpty {
      state.items = IdentifiedArray(uniqueElements: (state.items.elements + items).sorted(by: Self.displayOrder))
    }
    if let pending = state.pendingRemoval, pending.items.isEmpty, pending.reason == .cleared {
      state.pendingRemoval = nil
    }
  }

  /// Undoes the pending removal: what it set aside comes back. (An item copied again meanwhile is already back, see
  /// `.copied`.)
  private func putBack(_ state: inout State) {
    guard let pending = state.pendingRemoval else { return }
    bringBack(pending.items.filter { state.items[id: $0.id] == nil }, &state)
    state.pendingRemoval = nil
  }

  /// The removal Undo could take back is final: its items' rows and image folders go. Its timer, if still running,
  /// later finds nothing to settle; a new removal's timer replaces it.
  private func settlePendingRemoval(_ state: inout State) -> Effect<Action> {
    guard let pending = state.pendingRemoval else { return .none }
    state.pendingRemoval = nil
    return remove(pending.items, &state)
  }

  /// Adds a new item where it belongs, on top of the unpinned ones, then removes what has to go. No sort: the history
  /// stays in `displayOrder` as it is.
  private func insert(_ item: ClipboardItem, _ state: inout State) -> Effect<Action> {
    state.items.insert(item, at: state.items.index(forNew: item))
    save(item.isConcealed ? [] : [.insert(item)], &state)
    return prune(&state)
  }

  /// Reads the next image waiting, unless one is being read: its PNG file and Vision both off the main thread, one
  /// image at a time. An image that left the history meanwhile, or turned secret, is skipped unread. A failed read is
  /// logged without its text, and the image stays unread; there is no retry.
  private func readNextImage(_ state: inout State) -> Effect<Action> {
    guard state.readingImage == nil else { return .none }
    while !state.imagesToRead.isEmpty {
      let id = state.imagesToRead.removeFirst()
      guard let item = state.itemOrSetAside(id), !item.isConcealed, let url = item.imageURL else { continue }
      state.readingImage = id
      return .run { [files, textRecognition] send in
        let text = try await textRecognition.recognizeForSearch(try await files.read(url))
        await send(.imageRead(id, body: ClipboardItem.imageSearchBody(text)))
      } catch: { error, send in
        logger.error("Reading the text of a copied image failed: \(error, privacy: .public)")
        await send(.imageRead(id, body: nil))
      }
      .cancellable(id: CancelID.imageText, cancelInFlight: true)
    }
    return .none
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
  ) -> Effect<Action> {
    guard var item = state.items.remove(id: id) else { return .none }
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
    // Time has passed since the last check.
    return prune(&state)
  }

  /// What is kept about items that are no longer shown.
  private func forget(_ ids: Set<ClipboardItem.ID>, _ state: inout State) {
    state.unavailable.subtract(ids)
    state.revealed.subtract(ids)
    if let wholeText = state.wholeText, ids.contains(wholeText.id) {
      state.wholeText = nil
    }
  }

  /// Items that left the history for good: forgets them, deletes their rows, then their image folders; referenced files
  /// are never touched. In a session that keeps the history in memory only, just the image folders go.
  private func remove(_ items: [ClipboardItem], _ state: inout State) -> Effect<Action> {
    guard !items.isEmpty else { return .none }
    forget(Set(items.map(\.id)), &state)
    let folders = items.compactMap { $0.imageURL?.deletingLastPathComponent() }
    // A secret has no row.
    save([.delete(items.filter { !$0.isConcealed }.map(\.id), folders: folders)], &state)
    // No write removes the folders of a history kept in memory only: they go now.
    return state.isLoaded && state.savesToDisk ? .none : removeFolders(folders)
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
  /// history has been read, and never in a session that keeps the history in memory only: there a search is run again
  /// instead, as no `.written` comes to do it.
  private func save(_ writes: [HistoryWrite], _ state: inout State) {
    guard state.isLoaded, !writes.isEmpty else { return }
    guard state.savesToDisk else {
      state.searchIsBehind = true
      return
    }
    state.queuedWrites += writes
  }

  /// Writes the queued changes as one batch, unless a batch is being written (its `.written` comes first, and then
  /// this writes the rest) or a failed one waits for its pause. One batch at a time is what keeps the order: an insert
  /// followed by a delete of the same item never leaves its row behind. Image folders go once their rows are gone.
  private func writeQueued(_ state: inout State) -> Effect<Action> {
    guard state.writing == 0, !state.waitsToRetry, !state.queuedWrites.isEmpty else { return .none }
    let batch = state.queuedWrites
    state.writing = batch.count
    // One line in the log for a run of failures, not one per attempt.
    let reportsFailure = state.failedWrites == 0
    return .run { [files] send in
      let outcome = await Self.write(batch, to: database, reportsFailure: reportsFailure)
      for folder in outcome.folders {
        await files.remove(folder)
      }
      await send(.written(done: outcome.done, previews: outcome.previews, failed: outcome.failed))
    }
  }

  /// What writing a batch came to.
  struct WriteOutcome {
    /// Changes of the batch, from the first, that are done: in the database, or left out as they can never be written.
    var done = 0
    var previews: [ClipboardItem.ID: String] = [:]
    /// Image folders whose rows are gone.
    var folders: [URL] = []
    /// The changes after `done` failed on the database's state (busy, full, I/O…) and are written again later.
    var failed = false
  }

  /// Writes a batch in one transaction, so it lands whole or not at all. When a change in it can never be written (the
  /// data breaks a rule, `HistoryWrite.isRefusedForGood`), the changes are written again one at a time, and only one
  /// that fails on its own is left out, with a line in the log; the others still go in order.
  static func write(_ batch: [HistoryWrite], to database: any DatabaseWriter, reportsFailure: Bool) async -> WriteOutcome {
    do {
      let (previews, folders) = try await database.write { db in try HistoryWrite.apply(batch, db) }
      return WriteOutcome(done: batch.count, previews: previews, folders: folders)
    } catch where HistoryWrite.isRefusedForGood(error) {
      var outcome = WriteOutcome()
      for write in batch {
        do {
          let (previews, folders) = try await database.write { db in try HistoryWrite.apply([write], db) }
          outcome.previews.merge(previews) { _, new in new }
          outcome.folders += folders
        } catch where HistoryWrite.isRefusedForGood(error) {
          logger.error("A change to the clipboard history can't be written and is left out: \(error, privacy: .public)")
        } catch {
          if reportsFailure { logFailure(error) }
          outcome.failed = true
          return outcome
        }
        outcome.done += 1
      }
      return outcome
    } catch {
      if reportsFailure { logFailure(error) }
      return WriteOutcome(failed: true)
    }
  }

  private static func logFailure(_ error: any Error) {
    logger.error("Saving the clipboard history failed; it is written again in a moment: \(error, privacy: .public)")
  }

  /// The pause before writing again after `failures` failed attempts in a row: 1 s, doubling, at most 60 s.
  static func retryPause(after failures: Int) -> Duration {
    .seconds(min(60, 1 << min(max(failures - 1, 0), 6)))
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
