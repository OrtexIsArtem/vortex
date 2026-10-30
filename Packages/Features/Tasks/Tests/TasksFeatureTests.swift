import ComposableArchitecture
import CoreGraphics
import Foundation
import GRDB
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureTasks

/// A white screen of 40 × 20 points at 2 pixels per point.
func testScreenshot() -> Screenshot {
  let context = CGContext(
    data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.setFillColor(CGColor(gray: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
  return Screenshot(image: ScreenImage(cgImage: context.makeImage()!, scale: 2), notch: nil, displayID: 1)
}

let telegram = FrontWindow(app: AppInfo(bundleID: "ru.keepcoder.Telegram", name: "Telegram"), windowTitle: "mobile-team")

@MainActor
struct TasksFeatureTests {
  let clock = TestClock()
  let now = LockIsolated(Date(timeIntervalSinceReferenceDate: 800_000_000))
  let database = VortexDatabase.inMemory()
  let written = LockIsolated<[URL: Data]>([:])
  let removed = LockIsolated<[URL]>([])
  let opened = LockIsolated<[String]>([])
  let posted = LockIsolated<[String]>([])
  /// The pages features asked the shell for.
  let pages = LockIsolated<[Permission]>([])
  let refreshes = LockIsolated(0)
  let relaunches = LockIsolated(0)
  /// macOS as the tests set it: Screen Recording granted unless a test says otherwise.
  let simulated: SimulatedPermissions = {
    let simulated = SimulatedPermissions()
    simulated.set(.screenRecording, to: .granted)
    return simulated
  }()
  let screenshots = LockIsolated(0)
  let shortcut = AsyncStream.makeStream(of: Void.self)

  func makeStore(_ state: TasksFeature.State = TasksFeature.State()) -> TestStoreOf<TasksFeature> {
    let store = TestStore(initialState: state) {
      TasksFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.date = DateGenerator { [now] in now.value }
      $0.calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
      }()
      $0.uuid = .incrementing
      $0.database = database
      $0.fileClient.write = { [written] data, url in written.withValue { $0[url] = data } }
      $0.fileClient.remove = { [removed] url in removed.withValue { $0.append(url) } }
      $0.fileClient.contents = { _ in [] }
      $0.fileClient.open = { [opened] url in opened.withValue { $0.append(url.absoluteString) } }
      $0.appsClient.open = { [opened] id, url in opened.withValue { $0.append(id + (url.map { " " + $0.absoluteString } ?? "")) } }
      $0.fileClient.read = { [written] url in
        guard let data = written.value[url] else { throw CocoaError(.fileNoSuchFile) }
        return data
      }
      $0.permissionPage.open = { [pages] permission in pages.withValue { $0.append(permission) } }
      $0.permissionsClient = .simulated(simulated)
      $0.permissionsClient.refresh = { [simulated, refreshes] in
        refreshes.withValue { $0 += 1 }
        simulated.refresh()
      }
      $0.systemClient.relaunch = { [relaunches] in relaunches.withValue { $0 += 1 } }
      $0.screenCaptureClient.captureScreenUnderPointer = { [screenshots] in
        screenshots.withValue { $0 += 1 }
        return testScreenshot()
      }
      $0.frontWindowClient.current = { telegram }
      $0.textRecognitionClient.recognize = { image in image.size.width < 40 ? "Fix the pay button\nsecond line" : "whole screen #mobile-team" }
      $0.hotkeyClient.presses = { [shortcut] _ in shortcut.stream }
      $0.notificationClient.requestAuthorization = {
        Issue.record("Tasks never asks whether Vortex may notify")
        return false
      }
      $0.notificationClient.post = { [posted] id, _, _, _ in posted.withValue { $0.append(id) } }
    }
    store.exhaustivity = .off
    return store
  }

  /// The shell has read the statuses, Screen Recording granted, unless a test says otherwise.
  init() {
    readStatuses(simulated.statuses)
  }

  /// Sets what the shell read from the simulated macOS, as `@Shared(.permissionStatuses)` (nil: no read yet).
  func readStatuses(_ statuses: [Permission: PermissionStatus]?) {
    @Shared(.permissionStatuses) var shared
    $shared.withLock { $0 = statuses ?? [:] }
  }

  /// Effects write in their own time: waits a little for what they do.
  func eventually(_ condition: @escaping @Sendable () async throws -> Bool) async throws {
    for _ in 0..<100 where !(try await condition()) {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(try await condition())
  }

  func savedIDs() async throws -> [TaskItem.ID] {
    try await database.read { db in try TaskItem.fetchAllReadable(db) }.map(\.id).sorted { $0.uuidString < $1.uuidString }
  }

  /// Presses the shortcut, frames a part and saves it, the way a user does in three actions.
  func captureTask(_ store: TestStoreOf<TasksFeature>, title: String? = nil, priority: TaskItem.Priority = .low) async {
    shortcut.continuation.yield()
    await store.receive(\.captureRequested)
    await store.receive(\.captureTaken)
    await store.send(.capture(.frameEnded(CGRect(x: 2, y: 2, width: 20, height: 10))))
    await store.receive(\.capture.frameTextRecognized)
    if let title { await store.send(.capture(.titleChanged(title))) }
    await store.send(.capture(.priorityChosen(priority)))
    await store.send(.capture(.saveTapped))
    await store.receive(\.capture.delegate.save)
    await store.receive(\.taskSaved)
    await store.receive(\.textRecognized)
  }

  @Test
  func pictureFoldersWithoutATaskAreRemovedAtStart() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store)
    await store.send(.stop)
    let task = try #require(store.state.tasks.first)
    let orphan = TaskItem.folder.appending(path: "ORPHAN", directoryHint: .isDirectory)

    let relaunched = makeStore()
    relaunched.dependencies.fileClient.contents = { _ in [task.folderURL, orphan] }
    await relaunched.send(.start)
    await relaunched.receive(\.loaded)
    await relaunched.send(.stop)
    #expect(removed.value == [orphan])
  }

  @Test
  func theLastDeletedTasksPicturesGoAtTheNextStart() async {
    // Vortex quit while the deletion could still be taken back: no task is left, only its pictures.
    let orphan = TaskItem.folder.appending(path: "DELETED", directoryHint: .isDirectory)
    let store = makeStore()
    store.dependencies.fileClient.contents = { _ in [orphan] }
    await store.send(.start)
    await store.receive(\.loaded)
    await store.send(.stop)
    #expect(removed.value == [orphan])
  }

  @Test
  func aDatabaseOnlyInMemoryRemovesNoPictureFolder() async {
    // Its file didn't open: the pictures are then all that is left.
    let store = makeStore()
    store.dependencies.databaseIsOnDisk = false
    store.dependencies.fileClient.contents = { _ in [TaskItem.folder.appending(path: "UNREAD", directoryHint: .isDirectory)] }
    await store.send(.start)
    await store.receive(\.loaded)
    await store.send(.stop)
    #expect(removed.value.isEmpty)
  }

  @Test
  func theShortcutFreezesTheScreenAndReturnSavesTheTaskWithItsSourceAndText() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    shortcut.continuation.yield()
    await store.receive(\.captureRequested)
    await store.receive(\.captureTaken)
    #expect(store.state.capture?.source == telegram)
    #expect(store.state.capture?.title == TaskItem.defaultTitle(number: 1))
    await store.send(.capture(.frameEnded(CGRect(x: 2, y: 2, width: 20, height: 10))))
    await store.receive(\.capture.frameTextRecognized)
    #expect(store.state.capture?.isFramed == true)
    #expect(store.state.capture?.suggestion == "Fix the pay button")
    await store.send(.capture(.saveTapped))
    await store.receive(\.capture.delegate.save)
    #expect(store.state.capture == nil)
    await store.receive(\.taskSaved)
    await store.receive(\.textRecognized)
    let task = try #require(store.state.tasks.first)
    #expect(task.number == 1)
    #expect(task.title == TaskItem.defaultTitle(number: 1))
    #expect(task.source == telegram)
    #expect(task.cropWidth == 20)
    #expect(task.text == "Fix the pay button\nsecond line\nwhole screen #mobile-team")
    #expect(written.value.keys.map(\.lastPathComponent).sorted() == ["crop.png", "screen.heic"])
    let saved = try await database.read { db in try TaskItem.fetchAllReadable(db) }
    #expect(saved == [task])
    await store.send(.stop)
  }

  @Test
  func theSuggestionBecomesTheTitleAndAnEmptyTitleIsTheDefault() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    shortcut.continuation.yield()
    await store.receive(\.captureTaken)
    await store.send(.capture(.frameEnded(CGRect(x: 2, y: 2, width: 20, height: 10))))
    await store.receive(\.capture.frameTextRecognized)
    await store.send(.capture(.suggestionTapped))
    #expect(store.state.capture?.title == "Fix the pay button")
    await store.send(.capture(.titleChanged("   ")))
    await store.send(.capture(.saveTapped))
    await store.receive(\.taskSaved)
    #expect(store.state.tasks.first?.title == TaskItem.defaultTitle(number: 1))
    await store.send(.stop)
  }

  @Test
  func aClickIsNoFrameAndRetakeDrawsAgainOnTheSameFrozenScreen() async {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    shortcut.continuation.yield()
    await store.receive(\.captureTaken)
    await store.send(.capture(.frameEnded(CGRect(x: 5, y: 5, width: 3, height: 3))))
    #expect(store.state.capture?.isFramed == false)
    #expect(store.state.capture?.frame == nil)
    await store.send(.capture(.frameEnded(CGRect(x: 30, y: 15, width: -20, height: -10))))
    #expect(store.state.capture?.frame == CGRect(x: 10, y: 5, width: 20, height: 10))
    let screenshot = store.state.capture?.screenshot
    await store.send(.capture(.retakeTapped))
    #expect(store.state.capture?.isFramed == false)
    #expect(store.state.capture?.screenshot == screenshot)
    await store.send(.capture(.cancelTapped))
    await store.receive(\.capture.delegate.cancel)
    #expect(store.state.capture == nil)
    #expect(store.state.tasks.isEmpty)
    await store.send(.stop)
  }

  /// «+» and the shortcut without Screen Recording: the shell's page, never macOS's prompt, no notification, nothing
  /// taken; the mark shows on «+».
  @Test
  func withScreenRecordingOffANewTaskOpensThePageAndNeverAsksMacOS() async {
    simulated.set(.screenRecording, to: .denied)
    readStatuses(simulated.statuses)
    let store = makeStore()
    #expect(store.state.showsScreenRecordingWarning)
    await store.send(.start)
    await store.receive(\.loaded)
    await store.send(.captureRequested)
    shortcut.continuation.yield()
    await store.receive(\.captureRequested)
    await store.finish(timeout: .seconds(5))
    #expect(pages.value == [.screenRecording, .screenRecording])
    #expect(store.state.capture == nil)
    #expect(store.state.isStartingCapture == false)
    #expect(screenshots.value == 0)
    #expect(simulated.state.events.isEmpty)
    #expect(posted.value.isEmpty)
    #expect(opened.value.isEmpty)
    await store.send(.stop)
  }

  /// Granted for the next launch only: «+» starts nothing and opens the page in its ↻ state, without yellow.
  @Test
  func screenRecordingThatWorksAfterARestartOpensThePageWithoutAMark() async {
    simulated.set(.screenRecording, to: .notAsked)
    simulated.request(.screenRecording)
    simulated.toggle(.screenRecording, on: true)
    #expect(simulated.statuses[.screenRecording] == .grantedAfterRestart)
    readStatuses(simulated.statuses)
    let store = makeStore()
    #expect(!store.state.showsScreenRecordingWarning)
    await store.send(.start)
    await store.receive(\.loaded)
    await store.send(.captureRequested).finish()
    #expect(pages.value == [.screenRecording])
    #expect(screenshots.value == 0)
    await store.send(.stop)
  }

  /// While Vortex is blocked, the shortcut asks for the page and the shell shows its blocking page.
  @Test
  func whileBlockedTheShortcutOpensThePageInsteadOfCapturing() async {
    readStatuses(simulated.statuses)
    @Shared(.appBlocked) var appBlocked
    $appBlocked.withLock { $0 = true }
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    shortcut.continuation.yield()
    await store.receive(\.captureRequested)
    await store.finish(timeout: .seconds(5))
    #expect(pages.value == [.screenRecording])
    #expect(screenshots.value == 0)
    #expect(store.state.capture == nil)
    await store.send(.stop)
  }

  /// Before the shell's first read there is no mark, and a press reads the status once, which never prompts.
  @Test
  func beforeTheFirstReadAPressWaitsForItAndDecidesBlockedModeToo() async {
    readStatuses(nil)
    let store = makeStore()
    #expect(!store.state.showsScreenRecordingWarning)
    await store.send(.start)
    await store.receive(\.loaded)
    await store.send(.captureRequested)
    #expect(pages.value.isEmpty)
    #expect(screenshots.value == 0)

    // The shell's first read: Screen Recording on, but Vortex blocked: the page, no capture.
    @Shared(.appBlocked) var appBlocked
    $appBlocked.withLock { $0 = true }
    readStatuses(simulated.statuses)
    await store.receive(\.captureRequested)
    await store.finish(timeout: .seconds(5))
    #expect(pages.value == [.screenRecording])
    #expect(screenshots.value == 0)
    #expect(simulated.state.events.isEmpty)
    await store.send(.stop)
  }

  @Test
  func beforeTheFirstReadAPressCapturesOnceTheReadAllowsIt() async {
    readStatuses(nil)
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await store.send(.captureRequested)
    readStatuses(simulated.statuses)
    await store.receive(\.captureRequested)
    await store.receive(\.captureTaken)
    #expect(screenshots.value == 1)
    #expect(pages.value.isEmpty)
    await store.send(.stop)
  }

  /// The settings row: "Turn on" opens the page, "Restart Vortex" relaunches, and the section re-reads.
  @Test
  func theSettingsRowOpensThePageRestartsAndReadsAgain() async {
    let store = makeStore()
    await store.send(.settingsShown).finish()
    #expect(refreshes.value == 1)
    await store.send(.turnOnTapped(.screenRecording)).finish()
    #expect(pages.value == [.screenRecording])
    await store.send(.restartTapped).finish()
    #expect(relaunches.value == 1)
    #expect(simulated.state.events.isEmpty)
  }

  /// The mark on «+» follows the status: only `notGranted` is yellow.
  @Test
  func theMarkOnPlusShowsOnlyWhileScreenRecordingIsOff() {
    for (status, shows) in [(PermissionStatus?.none, false), (.granted, false), (.grantedAfterRestart, false), (.notNeeded, false), (.notGranted, true)] {
      readStatuses(status.map { [.screenRecording: $0] })
      #expect(TasksFeature.State().showsScreenRecordingWarning == shows)
    }
  }

  @Test
  func aPressWhileCapturingDoesNothing() async {
    var starting = TasksFeature.State()
    starting.isEnabled = true
    starting.isStartingCapture = true
    let store = makeStore(starting)
    // While the screen is being taken.
    await store.send(.captureRequested).finish()
    #expect(screenshots.value == 0)
    // While the frozen screen shows.
    await store.send(.start)
    await store.send(.captureTaken(testScreenshot(), telegram))
    await store.send(.captureRequested).finish()
    #expect(screenshots.value == 0)
    #expect(store.state.capture != nil)
    await store.send(.stop)
  }

  @Test
  func numbersGoOnFromTheHighestEverGiven() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store)
    await captureTask(store)
    let second = try #require(store.state.tasks.first { $0.number == 2 })
    await store.send(.deleteTapped(second.id))
    shortcut.continuation.yield()
    await store.receive(\.captureTaken)
    #expect(store.state.capture?.number == 3)
    await store.send(.stop)
  }

  @Test
  func doneLeavesTheActiveListAndCanBeTakenBackForAMoment() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store)
    let task = try #require(store.state.tasks.first)
    await store.send(.doneTapped(task.id))
    #expect(store.state.tasks[id: task.id]?.isDone == true)
    #expect(store.state.undoable == .done(task.id))
    #expect(store.state.visibleTasks(now: now.value, calendar: .current).isEmpty)
    await store.send(.undoTapped)
    #expect(store.state.tasks[id: task.id]?.isDone == false)
    await store.send(.doneTapped(task.id))
    await clock.advance(by: TasksFeature.undoTime)
    await store.receive(\.undoExpired)
    #expect(store.state.undoable == nil)
    var filter = TaskFilter()
    filter.status = .done
    await store.send(.filterChanged(filter))
    #expect(store.state.visibleTasks(now: now.value, calendar: .current).map(\.id) == [task.id])
    await store.send(.stop)
  }

  @Test
  func aDeletedTaskCanBeTakenBackForAMomentThenItsPicturesGo() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store)
    let task = try #require(store.state.tasks.first)
    await store.send(.deleteTapped(task.id))
    #expect(store.state.tasks.isEmpty)
    #expect(store.state.undoable == .deleted([task]))
    try await eventually { try await self.savedIDs().isEmpty }
    #expect(!removed.value.contains(task.folderURL))
    await store.send(.undoTapped)
    #expect(store.state.tasks.map(\.id) == [task.id])
    try await eventually { try await self.savedIDs() == [task.id] }
    #expect(try await database.read { db in try TaskItem.fetchAllReadable(db) } == [task])
    // Once it can't be taken back, the pictures go too.
    await store.send(.deleteTapped(task.id))
    await clock.advance(by: TasksFeature.undoTime)
    await store.receive(\.undoExpired)
    #expect(store.state.undoable == nil)
    try await eventually { [removed] in removed.value.contains(task.folderURL) }
    #expect(try await savedIDs().isEmpty)
    await store.send(.stop)
  }

  @Test
  func textRecognizedWhileATaskIsDeletedComesBackWithIt() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store)
    let task = try #require(store.state.tasks.first)
    await store.send(.deleteTapped(task.id))
    await store.send(.textRecognized(task.id, "read late"))
    await store.send(.undoTapped)
    #expect(store.state.tasks[id: task.id]?.text == "read late")
    try await eventually {
      try await self.database.read { db in try TaskItem.fetchAllReadable(db) }.map(\.text) == ["read late"]
    }
    await store.send(.stop)
  }

  @Test
  func clearingDoneDeletesTheDoneTasksTheListShowsAndTheLastClearCanBeTakenBack() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store, priority: .high)
    await captureTask(store, priority: .low)
    await captureTask(store)
    let high = try #require(store.state.tasks.first { $0.number == 1 })
    let low = try #require(store.state.tasks.first { $0.number == 2 })
    let active = try #require(store.state.tasks.first { $0.number == 3 })
    await store.send(.doneTapped(high.id))
    await store.send(.doneTapped(low.id))
    // The active list has nothing to clear.
    await store.send(.clearDoneTapped)
    #expect(store.state.tasks.count == 3)
    var filter = TaskFilter()
    filter.status = .done
    filter.priority = .high
    await store.send(.filterChanged(filter))
    await store.send(.clearDoneTapped)
    #expect(store.state.tasks.map(\.number).sorted() == [2, 3])
    filter.priority = nil
    await store.send(.filterChanged(filter))
    await store.send(.clearDoneTapped)
    #expect(store.state.tasks.map(\.id) == [active.id])
    #expect(!store.state.showsAny(now: now.value, calendar: .current))
    try await eventually { try await self.savedIDs() == [active.id] }
    // The clear before the last is final, pictures and all; the last one comes back.
    try await eventually { [removed] in removed.value.contains(high.folderURL) }
    #expect(!removed.value.contains(low.folderURL))
    await store.send(.undoTapped)
    #expect(store.state.tasks.map(\.number).sorted() == [2, 3])
    #expect(store.state.showsAny(now: now.value, calendar: .current))
    try await eventually { try await self.savedIDs() == [low.id, active.id].sorted { $0.uuidString < $1.uuidString } }
    await store.send(.stop)
  }

  @Test
  func theListPutsHighPriorityFirstNewestFirstWithinIt() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store, title: "old low")
    now.withValue { $0 += 60 }
    await captureTask(store, title: "high", priority: .high)
    now.withValue { $0 += 60 }
    await captureTask(store, title: "new low")
    let titles = store.state.visibleTasks(now: now.value, calendar: .current).map(\.title)
    #expect(titles == ["high", "new low", "old low"])
    await store.send(.stop)
  }

  @Test
  func searchFindsTasksByTitleRecognizedTextAppAndWindowTitle() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store, title: "Оплата на iPhone SE")
    for (query, found) in [("оплата", 1), ("#MOBILE-team", 1), ("telegram pay", 1), ("mobile-team", 1), ("slack", 0)] {
      await store.send(.queryChanged(query))
      #expect(store.state.visibleTasks(now: now.value, calendar: .current).count == found, "\(query)")
    }
    await store.send(.stop)
  }

  @Test
  func periodsCountCalendarDays() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12))!
    let lateYesterday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 23))!
    let sixDaysAgo = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 0))!
    let weekAgo = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 23))!
    #expect(TasksFeature.State.isIn(.today, noon, now: noon, calendar: calendar))
    #expect(!TasksFeature.State.isIn(.today, lateYesterday, now: noon, calendar: calendar))
    #expect(TasksFeature.State.isIn(.yesterday, lateYesterday, now: noon, calendar: calendar))
    #expect(TasksFeature.State.isIn(.week, sixDaysAgo, now: noon, calendar: calendar))
    #expect(!TasksFeature.State.isIn(.week, weekAgo, now: noon, calendar: calendar))
  }

  @Test
  func doneTasksGoWithTheirPicturesAfterThirtyDays() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store)
    let task = try #require(store.state.tasks.first)
    await store.send(.doneTapped(task.id))
    now.withValue { $0 += TimeInterval(TasksFeature.keptDays * 86_400 + 60) }
    await store.send(.tabShown).finish()
    #expect(store.state.tasks.isEmpty)
    #expect(removed.value.contains(task.folderURL))
    #expect(try await database.read { db in try TaskItem.fetchAllReadable(db) }.isEmpty)
    await store.send(.stop)
  }

  @Test
  func theSourceOpensThePageOrBringsTheAppForward() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store)
    let task = try #require(store.state.tasks.first)
    await store.send(.openSourceTapped(task.id)).finish()
    #expect(opened.value == ["ru.keepcoder.Telegram"])
    await store.send(.stop)
  }

  @Test
  func theWholeScreenShowsWithTheFramedPartAndClosesAgain() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store)
    let task = try #require(store.state.tasks.first)
    // A frame of 20 × 10 at 2, 2 on a screen of 40 × 20 points.
    #expect(task.cropArea == CGRect(x: 0.05, y: 0.1, width: 0.5, height: 0.5))
    await store.send(.screenTapped(task.id))
    await store.receive(\.screenLoaded)
    #expect(store.state.screen?.image?.cgImage.width == 80)
    await store.send(.screenClosed)
    #expect(store.state.screen == nil)
    // A second time closes it, and so does the shortcut, before the screen freezes.
    await store.send(.screenTapped(task.id))
    await store.send(.screenTapped(task.id))
    #expect(store.state.screen == nil)
    await store.send(.screenTapped(task.id))
    await store.receive(\.screenLoaded)
    shortcut.continuation.yield()
    await store.receive(\.captureRequested)
    #expect(store.state.screen == nil)
    await store.send(.stop)
  }

  @Test
  func aDoubleClickStillShowsTheWholeScreenAndACaptureKeepsItAway() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store)
    let task = try #require(store.state.tasks.first)
    // The second click comes while the picture is read.
    let reading = AsyncStream.makeStream(of: Void.self)
    store.dependencies.fileClient.read = { [written] url in
      for await _ in reading.stream { break }
      guard let data = written.value[url] else { throw CocoaError(.fileNoSuchFile) }
      return data
    }
    await store.send(.screenTapped(task.id))
    await store.send(.screenTapped(task.id))
    reading.continuation.yield()
    await store.receive(\.screenLoaded)
    #expect(store.state.screen?.image != nil)
    await store.send(.screenClosed)
    // Neither while the screen is taken nor while it is frozen.
    let taking = AsyncStream.makeStream(of: Void.self)
    store.dependencies.screenCaptureClient.captureScreenUnderPointer = {
      for await _ in taking.stream { break }
      return testScreenshot()
    }
    shortcut.continuation.yield()
    await store.receive(\.captureRequested)
    await store.send(.screenTapped(task.id))
    #expect(store.state.screen == nil)
    taking.continuation.yield()
    await store.receive(\.captureTaken)
    await store.send(.screenTapped(task.id))
    #expect(store.state.screen == nil)
    await store.send(.capture(.cancelTapped))
    await store.send(.stop)
  }

  @Test
  func aWholeScreenShownGoesWithItsTaskAfterThirtyDays() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store)
    let task = try #require(store.state.tasks.first)
    await store.send(.doneTapped(task.id))
    await store.send(.screenTapped(task.id))
    await store.receive(\.screenLoaded)
    now.withValue { $0 += TimeInterval(TasksFeature.keptDays * 86_400 + 60) }
    await store.send(.tabShown).finish()
    #expect(store.state.tasks.isEmpty)
    #expect(store.state.screen == nil)
    await store.send(.stop)
  }

  @Test
  func aWholeScreenThatCanNotBeReadDoesNotShow() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store)
    let task = try #require(store.state.tasks.first)
    written.withValue { $0[task.screenURL] = nil }
    await store.send(.screenTapped(task.id))
    await store.receive(\.screenLoaded)
    #expect(store.state.screen == nil)
    await store.send(.stop)
  }

  @Test
  func editsInTheCardAreSavedAndAnEmptiedTitleComesBack() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store)
    let task = try #require(store.state.tasks.first)
    await store.send(.titleChanged(task.id, ""))
    await store.send(.titleCommitted(task.id)).finish()
    #expect(store.state.tasks[id: task.id]?.title == TaskItem.defaultTitle(number: 1))
    await store.send(.priorityChanged(task.id, .high)).finish()
    let saved = try await database.read { db in try TaskItem.fetchAllReadable(db) }
    #expect(saved.first?.priority == .high)
    #expect(saved.first?.title == TaskItem.defaultTitle(number: 1))
    await store.send(.stop)
  }

  @Test
  func aTitleSavedAfterThePauseNeverUndoesOtherChangesMadeMeanwhile() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store)
    let task = try #require(store.state.tasks.first)
    let typing = await store.send(.titleChanged(task.id, "Pay button"))
    await store.send(.priorityChanged(task.id, .high)).finish()
    await store.send(.doneTapped(task.id))
    await clock.advance(by: .milliseconds(400))
    await typing.finish()
    let saved = try #require(try await database.read { db in try TaskItem.fetchAllReadable(db) }.first)
    #expect(saved.title == "Pay button")
    #expect(saved.priority == .high)
    #expect(saved.isDone)
    #expect(saved.text == task.text)
    await store.send(.stop)
  }

  @Test
  func leavingTheCardWithAnEmptiedTitleSavesTheDefault() async throws {
    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    await captureTask(store, title: "Pay button")
    let task = try #require(store.state.tasks.first)
    await store.send(.taskTapped(task.id))
    await store.send(.titleChanged(task.id, "  "))
    #expect(store.state.tasks[id: task.id]?.displayTitle == TaskItem.defaultTitle(number: 1))
    await store.send(.backTapped).finish()
    #expect(store.state.tasks[id: task.id]?.title == TaskItem.defaultTitle(number: 1))
    let saved = try await database.read { db in try TaskItem.fetchAllReadable(db) }
    #expect(saved.first?.title == TaskItem.defaultTitle(number: 1))
    await store.send(.stop)
  }
}
