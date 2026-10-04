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

  @ObservableState
  public struct State: Equatable {
    /// Pinned items first, then the others; newest first in both groups.
    public var items: IdentifiedArrayOf<ClipboardItem> = []
    var isLoaded = false
    /// False when the saved history could not be read: this session keeps it in memory only, so nothing on disk is
    /// overwritten.
    var savesToDisk = true
    /// Items whose files are gone.
    var unavailable: Set<ClipboardItem.ID> = []
    /// Concealed items the user is looking at; hidden again whenever the window opens.
    var revealed: Set<ClipboardItem.ID> = []
    /// The item just copied again, marked for a moment.
    var justCopied: ClipboardItem.ID?
    /// Running apps, offered when the user adds an app to ignore.
    var runningApps: [AppInfo] = []
    @Shared(.clipboardSettings) var settings

    public init() {}
  }

  public enum Action: Equatable, Sendable {
    case start
    case stop
    case loaded([ClipboardItem])
    case loadFailed
    case copied(ClipboardCopy)
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
  }

  @Dependency(\.appsClient) var apps
  @Dependency(\.continuousClock) var clock
  @Dependency(\.database) var database
  @Dependency(\.date.now) var now
  @Dependency(\.fileClient) var files
  @Dependency(\.pasteboardClient) var pasteboard
  @Dependency(\.uuid) var uuid

  private enum CancelID {
    case load
    case watch
    case save
    case copiedMark
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .start:
        guard !state.isLoaded else { return watch() }
        return .run { [files] send in
          try await database.migrate(ClipboardItem.migrator)
          let (items, savedIDs) = try await database.read { db in
            (try ClipboardItem.fetchAllReadable(db), try ClipboardItem.savedIDs(db))
          }
          // Image folders whose rows are gone, after a crash or a failed save. Before watching starts,
          // so a new image is never taken for one of them.
          for folder in await files.contents(ClipboardItem.imagesFolder) where !savedIDs.contains(folder.lastPathComponent) {
            await files.remove(folder)
          }
          await send(.loaded(items))
        } catch: { error, send in
          logger.error("Loading the clipboard history failed: \(error, privacy: .public)")
          await send(.loadFailed)
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)

      case .stop:
        return .merge(.cancel(id: CancelID.load), .cancel(id: CancelID.watch))

      case let .loaded(items):
        state.items = IdentifiedArray(items, uniquingIDsWith: { first, _ in first })
        state.items.sort(by: Self.displayOrder)
        state.isLoaded = true
        return watch()

      case .loadFailed:
        state.isLoaded = true
        state.savesToDisk = false
        return watch()

      case let .copied(copied):
        let copy = copied.copy
        let ignored = Set(state.settings.ignoredApps.map(\.bundleID))
        if !copy.frontApps.isDisjoint(with: ignored) || copy.source.map({ ignored.contains($0.bundleID) }) == true {
          return .none
        }
        if let existing = state.items.first(where: { $0.fingerprint == copied.fingerprint }) {
          return bump(existing.id, source: copy.source, isConcealed: copy.isConcealed, &state)
        }
        var item = ClipboardItem(
          id: uuid(),
          content: .text(""),
          source: copy.source,
          copiedAt: now,
          isConcealed: copy.isConcealed,
          fingerprint: copied.fingerprint
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
            removeFiles(of: [item]),
            bump(existing.id, source: item.source, isConcealed: item.isConcealed, &state)
          )
        }
        return insert(item, &state)

      case let .itemTapped(id):
        guard let item = state.items[id: id], !state.unavailable.contains(id) else { return .none }
        return .run { [files] send in
          let content: PasteboardContent
          switch item.content {
          case let .text(text): content = .text(text)
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
          .run { send in
            try await clock.sleep(for: .seconds(1.2))
            await send(.copiedMarkElapsed)
          }
          .cancellable(id: CancelID.copiedMark, cancelInFlight: true),
          bump(id, source: item.source, isConcealed: item.isConcealed, &state)
        )

      case let .pinTapped(id):
        state.items[id: id]?.isPinned.toggle()
        state.items.sort(by: Self.displayOrder)
        return save(state)

      case let .deleteTapped(id):
        guard let item = state.items.remove(id: id) else { return .none }
        state.unavailable.remove(id)
        state.revealed.remove(id)
        return .merge(removeFiles(of: [item]), save(state))

      case .clearTapped:
        let cleared = state.items.filter { !$0.isPinned }
        state.items.removeAll { !$0.isPinned }
        return .merge(removeFiles(of: Array(cleared)), save(state))

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
        return .run { send in await send(.runningAppsLoaded(apps.running())) }

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
  }

  /// Pinned first, then newest first.
  static func displayOrder(_ lhs: ClipboardItem, _ rhs: ClipboardItem) -> Bool {
    lhs.isPinned != rhs.isPinned ? lhs.isPinned : lhs.copiedAt > rhs.copiedAt
  }

  /// "Image 2026-10-04 at 14.03.12.png": the name the image has when dragged into another app.
  static func imageFileName(copiedAt date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return "Image \(formatter.string(from: date)).png"
  }

  private func watch() -> Effect<Action> {
    .run { send in
      for await copy in pasteboard.copies() {
        // Hashing an image is not for the main thread, so it happens here.
        await send(.copied(ClipboardCopy(copy)))
      }
    }
    .cancellable(id: CancelID.watch, cancelInFlight: true)
  }

  /// Adds a new item on top and drops the oldest unpinned ones beyond the limit.
  private func insert(_ item: ClipboardItem, _ state: inout State) -> Effect<Action> {
    state.items.append(item)
    state.items.sort(by: Self.displayOrder)
    let dropped = state.items.filter { !$0.isPinned }.dropFirst(Self.historyLimit)
    for item in dropped {
      state.items.remove(id: item.id)
      state.unavailable.remove(item.id)
      state.revealed.remove(item.id)
    }
    return .merge(removeFiles(of: Array(dropped)), save(state))
  }

  /// Moves an item copied again to the top of its group.
  private func bump(_ id: ClipboardItem.ID, source: AppInfo?, isConcealed: Bool, _ state: inout State) -> Effect<Action> {
    state.items[id: id]?.copiedAt = now
    state.items[id: id]?.source = source
    state.items[id: id]?.isConcealed = isConcealed
    state.items.sort(by: Self.displayOrder)
    return save(state)
  }

  /// Deletes the image files of items that are gone; referenced files are never touched.
  private func removeFiles(of items: [ClipboardItem]) -> Effect<Action> {
    let folders = items.compactMap { $0.imageURL?.deletingLastPathComponent() }
    guard !folders.isEmpty else { return .none }
    return .run { [files] _ in
      for folder in folders {
        await files.remove(folder)
      }
    }
  }

  /// Writes the history, secrets left out; a newer save cancels an older one that has not finished.
  private func save(_ state: State) -> Effect<Action> {
    guard state.savesToDisk else { return .none }
    let items = state.items.filter { !$0.isConcealed }
    return .run { _ in
      try await database.write { db in try ClipboardItem.save(Array(items), in: db) }
    } catch: { error, _ in
      logger.error("Saving the clipboard history failed: \(error, privacy: .public)")
    }
    .cancellable(id: CancelID.save, cancelInFlight: true)
  }
}

private let logger = Logger(subsystem: "io.github.ortexisartem.vortex", category: "clipboard")
