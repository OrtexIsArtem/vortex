import ComposableArchitecture
import Foundation
import GRDB
import os
import VortexCore
import VortexPlatform

extension Hotkey {
  /// Freezes the screen to frame a new task.
  static let captureTask = Hotkey("captureTask")
}

/// Which tasks the list shows.
public struct TaskFilter: Equatable, Sendable {
  public enum Period: CaseIterable, Sendable {
    case today
    case yesterday
    case week
    case all
  }

  public enum Status: CaseIterable, Sendable {
    case active
    case done
  }

  /// nil shows every priority.
  public var priority: TaskItem.Priority?
  public var period = Period.all
  public var status = Status.active

  public init() {}
}

/// A task's whole screen while it is shown over the display; `image` is nil until its picture is read.
struct TaskScreen: Equatable {
  let taskID: TaskItem.ID
  var image: ScreenImage?
}

/// Tasks taken from the screen: a shortcut freezes it, a frame picks the part that matters, Return saves it with the
/// app, window title and page it came from. The list filters and searches them, also by the text on their pictures,
/// which is recognized in the background.
@Reducer
public struct TasksFeature: Sendable {
  public static let id: FeatureID = "tasks"
  /// Done tasks are deleted with their pictures this many days after they were done.
  static let keptDays = 30
  /// How long marking a task done or deleting can be taken back.
  static let undoTime: Duration = .seconds(5)

  /// The last change, which can be taken back for `undoTime`; a new one makes it final.
  enum Undoable: Equatable {
    case done(TaskItem.ID)
    /// Their rows are gone; their pictures go once it can't be taken back.
    case deleted([TaskItem])
  }

  @ObservableState
  public struct State: Equatable {
    var tasks: IdentifiedArrayOf<TaskItem> = []
    var isLoaded = false
    var isEnabled = false
    /// The highest number given so far; the next task is shown with the one after it.
    var lastNumber = 0
    var filter = TaskFilter()
    var query = ""
    /// The task open in the tab; nil shows the list.
    var openTaskID: TaskItem.ID?
    /// The last change, while it can still be taken back.
    var undoable: Undoable?
    /// A task's whole screen, shown over the display.
    var screen: TaskScreen?
    /// The capture under way, from the frozen screen until it is saved or cancelled.
    var capture: CaptureFeature.State?
    /// The shortcut was pressed and the screen is being taken: another press waits for it.
    var isStartingCapture = false
    /// What macOS says about Screen Recording, read by the shell; the status decides whether «+» captures (S56).
    @SharedReader(.permissionStatuses) var permissionStatuses
    /// A required permission is off: the shortcut opens the shell's blocking page instead (S43).
    @SharedReader(.appBlocked) var appBlocked

    public init() {}

    var openTask: TaskItem? { openTaskID.flatMap { tasks[id: $0] } }

    /// «+» shows a yellow warning: Screen Recording reads off (S22.1). Not before the first read, nor for ↻ (S40).
    var showsScreenRecordingWarning: Bool {
      PermissionMark(permissionStatuses[.screenRecording]) == .warning
    }

    /// The tasks the list shows: filtered and searched; active ones by priority, newest first within one; done ones by
    /// when they were done.
    func visibleTasks(now: Date, calendar: Calendar) -> [TaskItem] {
      let words = query.split(whereSeparator: \.isWhitespace)
      return tasks
        .filter { shows($0, words: words, now: now, calendar: calendar) }
        .sorted { lhs, rhs in
          if filter.status == .done { return (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast) }
          return lhs.priority != rhs.priority ? lhs.priority > rhs.priority : lhs.createdAt > rhs.createdAt
        }
    }

    /// Whether the list shows any task, without sorting them.
    func showsAny(now: Date, calendar: Calendar) -> Bool {
      let words = query.split(whereSeparator: \.isWhitespace)
      return tasks.contains { shows($0, words: words, now: now, calendar: calendar) }
    }

    private func shows(_ task: TaskItem, words: [Substring], now: Date, calendar: Calendar) -> Bool {
      (filter.status == .done) == task.isDone
        && (filter.priority.map { $0 == task.priority } ?? true)
        && Self.isIn(filter.period, task.createdAt, now: now, calendar: calendar)
        && Self.matches(task, words)
    }

    static func isIn(_ period: TaskFilter.Period, _ date: Date, now: Date, calendar: Calendar) -> Bool {
      switch period {
      case .all:
        return true
      case .today:
        return calendar.isDate(date, inSameDayAs: now)
      case .yesterday:
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return false }
        return calendar.isDate(date, inSameDayAs: yesterday)
      case .week:
        guard let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) else { return true }
        return date >= start
      }
    }

    /// Every word is found in the title, the recognized text, the app, the window title or the page address.
    static func matches(_ task: TaskItem, _ words: [Substring]) -> Bool {
      let fields = [task.displayTitle, task.text, task.source.app?.name, task.source.windowTitle, task.source.url?.absoluteString]
        .compactMap { $0 }
      return words.allSatisfy { word in
        fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
      }
    }
  }

  public enum Action: Equatable, Sendable {
    case start
    case stop
    case loaded(tasks: [TaskItem], lastNumber: Int)
    case loadFailed
    /// The shortcut, the New button or a debug command: freeze the screen to frame a task.
    case captureRequested
    case captureTaken(Screenshot, FrontWindow)
    /// The screen couldn't be taken, or Screen Recording turned out to be off before the first read.
    case captureFailed
    case capture(CaptureFeature.Action)
    case taskSaved(TaskItem)
    case textRecognized(TaskItem.ID, String)
    case taskTapped(TaskItem.ID)
    case backTapped
    case titleChanged(TaskItem.ID, String)
    /// The title field lost focus or Return was pressed in it.
    case titleCommitted(TaskItem.ID)
    case priorityChanged(TaskItem.ID, TaskItem.Priority)
    /// Marks the task done, or active again.
    case doneTapped(TaskItem.ID)
    case undoTapped
    case undoExpired
    /// The bin on a row or in the card.
    case deleteTapped(TaskItem.ID)
    /// «Очистити список» in «Виконані»: deletes the done tasks the list shows.
    case clearDoneTapped
    case openSourceTapped(TaskItem.ID)
    /// The whole screen of the task, over the display, with the framed part marked; again closes it.
    case screenTapped(TaskItem.ID)
    case screenLoaded(TaskItem.ID, ScreenImage?)
    /// Esc, Space, Return or a click on the whole screen, or another app coming to the front.
    case screenClosed
    case filterChanged(TaskFilter)
    case queryChanged(String)
    /// The tab became visible: the window opened on it, or the user switched to it.
    case tabShown
    /// The section in Settings › Features appeared: the statuses are read again (S47).
    case settingsShown
    /// "Turn on" in the settings row of a permission that is off: the shell's page (S22.3, S23).
    case turnOnTapped(Permission)
    /// "Restart Vortex" in the row of a permission that works after a relaunch (S40).
    case restartTapped
  }

  @Dependency(\.appsClient) var apps
  @Dependency(\.calendar) var calendar
  @Dependency(\.continuousClock) var clock
  @Dependency(\.database) var database
  @Dependency(\.databaseIsOnDisk) var databaseIsOnDisk
  @Dependency(\.date.now) var now
  @Dependency(\.fileClient) var files
  @Dependency(\.frontWindowClient) var frontWindow
  @Dependency(\.hotkeyClient) var hotkeys
  @Dependency(\.permissionPage) var permissionPage
  @Dependency(\.permissionsClient) var permissions
  @Dependency(\.screenCaptureClient) var screenCapture
  @Dependency(\.systemClient) var system
  @Dependency(\.textRecognitionClient) var textRecognition
  @Dependency(\.uuid) var uuid

  private enum CancelID: Hashable {
    case load
    case shortcut
    case startCapture
    case undo
    /// The rows of the tasks just deleted, so taking them back never runs before they are gone.
    case deletion([TaskItem.ID])
    case screen
    case titleSave(TaskItem.ID)
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .start:
        state.isEnabled = true
        return state.isLoaded ? listenToShortcut() : .merge(listenToShortcut(), load())

      case .stop:
        state.isEnabled = false
        state.capture = nil
        state.isStartingCapture = false
        state.screen = nil
        return .merge(
          .cancel(id: CancelID.load),
          .cancel(id: CancelID.shortcut),
          .cancel(id: CancelID.startCapture),
          .cancel(id: CancelID.screen)
        )

      case let .loaded(tasks, lastNumber):
        state.tasks = IdentifiedArray(tasks, uniquingIDsWith: { first, _ in first })
        state.lastNumber = lastNumber
        state.isLoaded = true
        // Pictures whose text was not read before Vortex quit.
        let unread = tasks.filter { $0.text == nil }.map(recognizeSaved)
        return .merge([purgeOld(&state)] + unread)

      case .loadFailed:
        state.isLoaded = true
        return .none

      case .captureRequested:
        guard state.isEnabled, state.capture == nil, !state.isStartingCapture else { return .none }
        // While Vortex is blocked, the shell shows its blocking page whatever is asked for (S43).
        guard !state.appBlocked else { return openPage(.screenRecording) }
        guard let status = state.permissionStatuses[.screenRecording] else {
          // Before the shell's first read (S64): wait for it, then decide again, blocked mode included, as the shell
          // writes the statuses and `appBlocked` together.
          return .run { [statuses = state.$permissionStatuses] send in
            for await value in statuses.publisher.values where !value.isEmpty {
              await send(.captureRequested)
              return
            }
          }
          .cancellable(id: CancelID.startCapture, cancelInFlight: true)
        }
        // The status decides (S56): off, or granted only from the next launch, the page opens and nothing is taken;
        // Vortex never asks macOS itself (S23, S25, S40).
        guard Self.canCapture(status) else { return openPage(.screenRecording) }
        state.isStartingCapture = true
        // A whole screen shown now would lie under the frozen one.
        state.screen = nil
        return .run { send in
          // The app in front and what is open in it first: nothing of Vortex shows yet, so it is still the one the
          // user was in, and a browser's one-time Automation prompt is answered before the screen is taken.
          let source = await frontWindow.current()
          let screenshot = try await screenCapture.captureScreenUnderPointer()
          await send(.captureTaken(screenshot, source))
        } catch: { error, send in
          logger.error("Taking the screen failed: \(error, privacy: .public)")
          await send(.captureFailed)
        }
        .cancellable(id: CancelID.startCapture, cancelInFlight: true)

      case let .captureTaken(screenshot, source):
        state.isStartingCapture = false
        guard state.isEnabled else { return .none }
        state.capture = CaptureFeature.State(
          screenshot: screenshot,
          source: source,
          capturedAt: now,
          number: state.lastNumber + 1
        )
        return .none

      case .captureFailed:
        state.isStartingCapture = false
        return .none

      case let .capture(.delegate(.save(draft))):
        state.capture = nil
        return save(draft)

      case .capture(.delegate(.cancel)):
        state.capture = nil
        return .none

      case .capture:
        return .none

      case let .taskSaved(task):
        state.tasks[id: task.id] = task
        state.lastNumber = max(state.lastNumber, task.number)
        return .none

      case let .textRecognized(id, text):
        state.tasks[id: id]?.text = text
        // Deleted meanwhile: it comes back with its text.
        if case var .deleted(tasks) = state.undoable, let index = tasks.firstIndex(where: { $0.id == id }) {
          tasks[index].text = text
          state.undoable = .deleted(tasks)
        }
        return .none

      case let .taskTapped(id):
        state.openTaskID = id
        return .none

      case .backTapped:
        guard let id = state.openTaskID else { return .none }
        state.openTaskID = nil
        return commitTitle(id, &state)

      case let .titleChanged(id, title):
        guard state.tasks[id: id] != nil else { return .none }
        state.tasks[id: id]?.title = title
        // Written once typing pauses, so the writes never overtake one another; an emptied title is saved as "Task 13".
        let saved = state.tasks[id: id]?.displayTitle ?? title
        return update(id, "title", saved, after: .milliseconds(400))
          .cancellable(id: CancelID.titleSave(id), cancelInFlight: true)

      case let .titleCommitted(id):
        return commitTitle(id, &state)

      case let .priorityChanged(id, priority):
        guard let task = state.tasks[id: id], task.priority != priority else { return .none }
        state.tasks[id: id]?.priority = priority
        return update(id, "priority", priority.rawValue)

      case let .doneTapped(id):
        guard let task = state.tasks[id: id] else { return .none }
        let completedAt = task.isDone ? nil : now
        state.tasks[id: id]?.completedAt = completedAt
        guard completedAt != nil else {
          if state.undoable == .done(id) { state.undoable = nil }
          return update(id, "completedAt", completedAt)
        }
        // A done task leaves the active list; the list comes back, with a moment to take it back.
        var effects = [settleUndoable(&state), update(id, "completedAt", completedAt)]
        state.undoable = .done(id)
        if state.openTaskID == id {
          state.openTaskID = nil
          effects.append(commitTitle(id, &state))
        }
        effects.append(undoTimer())
        return .merge(effects)

      case .undoTapped:
        switch state.undoable {
        case let .done(id):
          guard state.tasks[id: id] != nil else { return .none }
          state.tasks[id: id]?.completedAt = nil
          state.undoable = nil
          return .merge(.cancel(id: CancelID.undo), update(id, "completedAt", nil as Date?))
        case let .deleted(tasks):
          state.undoable = nil
          for task in tasks {
            state.tasks[id: task.id] = task
          }
          return .merge(.cancel(id: CancelID.undo), .cancel(id: CancelID.deletion(tasks.map(\.id))), restore(tasks))
        case nil:
          return .none
        }

      case .undoExpired:
        return settleUndoable(&state)

      case let .deleteTapped(id):
        guard let task = state.tasks[id: id] else { return .none }
        return delete([task], &state)

      case .clearDoneTapped:
        guard state.filter.status == .done else { return .none }
        let tasks = state.visibleTasks(now: now, calendar: calendar)
        guard !tasks.isEmpty else { return .none }
        return delete(tasks, &state)

      case let .openSourceTapped(id):
        guard let source = state.tasks[id: id]?.source else { return .none }
        return .run { _ in
          // The browser the task came from opens the page; any other app comes to the front.
          if let app = source.app {
            await apps.open(app.bundleID, source.url)
          } else if let url = source.url {
            await files.open(url)
          }
        }

      case let .screenTapped(id):
        // It would lie under the frozen screen.
        guard state.capture == nil, !state.isStartingCapture else { return .none }
        if let screen = state.screen, screen.taskID == id {
          // The second click of a double click, while the picture is read, leaves it coming.
          guard screen.image != nil else { return .none }
          state.screen = nil
          return .cancel(id: CancelID.screen)
        }
        guard let task = state.tasks[id: id] else { return .none }
        state.screen = TaskScreen(taskID: id)
        return .run { send in
          // Read and decoded here, off the main thread, so it shows at once and whole.
          let data = try? await files.read(task.screenURL)
          await send(.screenLoaded(id, data.flatMap { ScreenImage(decoding: $0) }))
        }
        .cancellable(id: CancelID.screen, cancelInFlight: true)

      case let .screenLoaded(id, image):
        guard state.screen?.taskID == id else { return .none }
        guard let image else {
          logger.error("The whole screen of a task could not be read")
          state.screen = nil
          return .none
        }
        state.screen?.image = image
        return .none

      case .screenClosed:
        state.screen = nil
        return .cancel(id: CancelID.screen)

      case let .filterChanged(filter):
        state.filter = filter
        return .none

      case let .queryChanged(query):
        state.query = query
        return .none

      case .tabShown:
        return purgeOld(&state)

      case .settingsShown:
        return .run { _ in await permissions.refresh() }

      case let .turnOnTapped(permission):
        return openPage(permission)

      case .restartTapped:
        return .run { _ in await system.relaunch() }
      }
    }
    .ifLet(\.capture, action: \.capture) {
      CaptureFeature()
    }
  }

  /// A capture works now: granted, or not asked for on this Mac.
  static func canCapture(_ status: PermissionStatus) -> Bool {
    status == .granted || status == .notNeeded
  }

  /// The shell's page for a permission, instead of asking macOS (S23, S24).
  private func openPage(_ permission: Permission) -> Effect<Action> {
    .run { _ in await permissionPage.open(permission) }
  }

  private func listenToShortcut() -> Effect<Action> {
    .run { send in
      for await _ in hotkeys.presses(.captureTask) {
        await send(.captureRequested)
      }
    }
    .cancellable(id: CancelID.shortcut, cancelInFlight: true)
  }

  private func load() -> Effect<Action> {
    // `databaseIsOnDisk` is read in the effect: reading it opens the database, which stays off the main thread.
    .run { send in
      try await database.migrate(TaskItem.migrator)
      let (tasks, lastNumber, savedIDs) = try await database.read { db in
        (
          try TaskItem.fetchAllReadable(db),
          try TaskItem.lastNumber(db),
          try String.fetchSet(db, sql: "SELECT id FROM \(TaskItem.databaseTableName)")
        )
      }
      // Picture folders whose row is gone: Vortex stopped between writing the pictures and saving the row, or while a
      // deletion could still be taken back. Not while the database is only in memory: its file didn't open, and the
      // pictures are then all that is left.
      if databaseIsOnDisk {
        for folder in await files.contents(TaskItem.folder) where !savedIDs.contains(folder.lastPathComponent) {
          await files.remove(folder)
        }
      }
      await send(.loaded(tasks: tasks, lastNumber: lastNumber))
    } catch: { error, send in
      logger.error("Loading the tasks failed: \(error, privacy: .public)")
      await send(.loadFailed)
    }
    .cancellable(id: CancelID.load, cancelInFlight: true)
  }

  /// Writes the pictures, then the row, then recognizes the text on both pictures for search.
  private func save(_ draft: TaskDraft) -> Effect<Action> {
    let id = uuid()
    return .run { send in
      guard let part = draft.screenshot.image.cropped(to: draft.frame),
            let partData = part.pngData(),
            let screenData = draft.screenshot.image.heicData()
      else {
        logger.error("Encoding the pictures of a task failed")
        return
      }
      let new = TaskItem(
        id: id,
        number: draft.number,
        title: draft.title,
        priority: draft.priority,
        createdAt: draft.capturedAt,
        completedAt: nil,
        source: draft.source,
        cropWidth: part.size.width,
        cropHeight: part.size.height,
        cropX: draft.frame.minX,
        cropY: draft.frame.minY,
        screenWidth: draft.screenshot.image.size.width,
        screenHeight: draft.screenshot.image.size.height,
        text: nil
      )
      // Pictures first: a row without them would show an empty task.
      try await files.write(partData, new.cropURL)
      try await files.write(screenData, new.screenURL)
      let task = try await database.write { db in try TaskItem.insertNew(new, db) }
      await send(.taskSaved(task))
      let text = await recognizedText(part: part, screen: draft.screenshot.image, partText: draft.frameText)
      try await database.write { db in try Self.setText(text, of: id, db) }
      await send(.textRecognized(id, text))
    } catch: { error, _ in
      logger.error("Saving a task failed: \(error, privacy: .public)")
    }
  }

  /// Text of a task saved before its recognition finished.
  private func recognizeSaved(_ task: TaskItem) -> Effect<Action> {
    .run { send in
      let part = ScreenImage(contentsOf: task.cropURL)
      let screen = ScreenImage(contentsOf: task.screenURL)
      let text = await recognizedText(part: part, screen: screen, partText: nil)
      try await database.write { db in try Self.setText(text, of: task.id, db) }
      await send(.textRecognized(task.id, text))
    } catch: { error, _ in
      logger.error("Recognizing the text of a task failed: \(error, privacy: .public)")
    }
  }

  /// The part's text, then the whole screen's; a picture that fails to read adds nothing.
  private func recognizedText(part: ScreenImage?, screen: ScreenImage?, partText: String?) async -> String {
    var texts: [String] = []
    if let partText {
      texts.append(partText)
    } else if let part {
      texts.append((try? await textRecognition.recognize(part)) ?? "")
    }
    if let screen {
      texts.append((try? await textRecognition.recognize(screen)) ?? "")
    }
    return texts.filter { !$0.isEmpty }.joined(separator: "\n")
  }

  private static func setText(_ text: String, of id: TaskItem.ID, _ db: Database) throws {
    try db.execute(
      sql: "UPDATE \(TaskItem.databaseTableName) SET text = ? WHERE id = ?",
      arguments: [text, id.uuidString]
    )
  }

  /// Writes one change: only its own column, so it never overwrites another change written meanwhile, such as the
  /// recognized text or the done mark.
  private func update(
    _ id: TaskItem.ID,
    _ column: String,
    _ value: (any DatabaseValueConvertible & Sendable)?,
    after delay: Duration? = nil
  ) -> Effect<Action> {
    .run { _ in
      if let delay { try await clock.sleep(for: delay) }
      try await database.write { db in
        try db.execute(
          sql: "UPDATE \(TaskItem.databaseTableName) SET \(column) = ? WHERE id = ?",
          arguments: [value, id.uuidString]
        )
      }
    } catch: { error, _ in
      logger.error("Saving a task failed: \(error, privacy: .public)")
    }
  }

  /// Leaving the title: an emptied one is "Task 13" again, and it is saved now rather than after the pause.
  private func commitTitle(_ id: TaskItem.ID, _ state: inout State) -> Effect<Action> {
    guard let task = state.tasks[id: id] else { return .none }
    state.tasks[id: id]?.title = task.displayTitle
    return .merge(.cancel(id: CancelID.titleSave(id)), update(id, "title", task.displayTitle))
  }

  /// Deletes the tasks with a moment to take it back: their rows go now, so they stay gone if Vortex quits meanwhile
  /// (the pictures of rows that are gone are deleted at launch), their pictures once it can't be taken back.
  private func delete(_ tasks: [TaskItem], _ state: inout State) -> Effect<Action> {
    var effects = [settleUndoable(&state)]
    var deleted: [TaskItem] = []
    for var task in tasks {
      state.tasks.remove(id: task.id)
      if state.openTaskID == task.id { state.openTaskID = nil }
      if state.screen?.taskID == task.id { state.screen = nil }
      // An emptied title comes back as «Задача N», as on leaving the card.
      task.title = task.displayTitle
      deleted.append(task)
      effects.append(.cancel(id: CancelID.titleSave(task.id)))
    }
    state.undoable = .deleted(deleted)
    effects.append(deleteRows(deleted).cancellable(id: CancelID.deletion(deleted.map(\.id))))
    effects.append(undoTimer())
    return .merge(effects)
  }

  /// The change waiting to be taken back can't be any more: deleted tasks lose their pictures.
  private func settleUndoable(_ state: inout State) -> Effect<Action> {
    defer { state.undoable = nil }
    guard case let .deleted(tasks) = state.undoable else { return .none }
    return .run { _ in
      for task in tasks {
        await files.remove(task.folderURL)
      }
    }
  }

  private func undoTimer() -> Effect<Action> {
    .run { send in
      try await clock.sleep(for: Self.undoTime)
      await send(.undoExpired)
    }
    .cancellable(id: CancelID.undo, cancelInFlight: true)
  }

  private func deleteRows(_ tasks: [TaskItem]) -> Effect<Action> {
    .run { _ in
      try await database.write { db in
        for task in tasks {
          _ = try task.delete(db)
        }
      }
    } catch: { error, _ in
      // Taken back before the rows went: they stay.
      guard !(error is CancellationError) else { return }
      logger.error("Deleting tasks failed: \(error, privacy: .public)")
    }
  }

  /// Deleted tasks taken back: their rows again, as they were.
  private func restore(_ tasks: [TaskItem]) -> Effect<Action> {
    .run { _ in
      try await database.write { db in
        for task in tasks {
          try task.insert(db, onConflict: .replace)
        }
      }
    } catch: { error, _ in
      logger.error("Taking deleted tasks back failed: \(error, privacy: .public)")
    }
  }

  /// For good, rows first, then the pictures.
  private func deleteForGood(_ tasks: [TaskItem]) -> Effect<Action> {
    .run { _ in
      try await database.write { db in
        for task in tasks {
          _ = try task.delete(db)
        }
      }
      for task in tasks {
        await files.remove(task.folderURL)
      }
    } catch: { error, _ in
      logger.error("Deleting tasks failed: \(error, privacy: .public)")
    }
  }

  /// Done tasks older than `keptDays` go, with their pictures.
  private func purgeOld(_ state: inout State) -> Effect<Action> {
    guard let limit = calendar.date(byAdding: .day, value: -Self.keptDays, to: now) else { return .none }
    let old = state.tasks.filter { ($0.completedAt ?? .distantFuture) < limit }
    guard !old.isEmpty else { return .none }
    for task in old {
      state.tasks.remove(id: task.id)
      if state.screen?.taskID == task.id { state.screen = nil }
    }
    return deleteForGood(Array(old))
  }
}

private let logger = Logger(subsystem: "io.github.ortexisartem.vortex", category: "tasks")
