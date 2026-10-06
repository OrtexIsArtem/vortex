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
  let accessRequests = LockIsolated(0)
  let hasAccess = LockIsolated(true)
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
      $0.quickLookClient.toggle = { [opened] urls in opened.withValue { $0 += urls.map(\.lastPathComponent) } }
      $0.screenCaptureClient.hasAccess = { [hasAccess] in hasAccess.value }
      $0.screenCaptureClient.requestAccess = { [accessRequests] in
        accessRequests.withValue { $0 += 1 }
        return false
      }
      $0.screenCaptureClient.captureScreenUnderPointer = { [screenshots] in
        screenshots.withValue { $0 += 1 }
        return testScreenshot()
      }
      $0.frontWindowClient.current = { telegram }
      $0.textRecognitionClient.recognize = { image in image.size.width < 40 ? "Fix the pay button\nsecond line" : "whole screen #mobile-team" }
      $0.hotkeyClient.presses = { [shortcut] _ in shortcut.stream }
      $0.notificationClient.requestAuthorization = { true }
      $0.notificationClient.post = { [posted] id, _, _, _ in posted.withValue { $0.append(id) } }
    }
    store.exhaustivity = .off
    return store
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

  @Test
  func withoutScreenRecordingTheFirstCaptureAsksAndLaterOnesOpenSystemSettings() async {
    hasAccess.setValue(false)
    let store = makeStore()
    await store.send(.start)
    await store.send(.captureRequested)
    await store.receive(\.captureFailed)
    #expect(store.state.capture == nil)
    #expect(store.state.hasScreenAccess == false)
    #expect(accessRequests.value == 1)
    #expect(opened.value.isEmpty)
    // The system's prompt shows once ever; this is kept for the next launches too.
    #expect(store.state.settings.askedForScreenRecording)
    await store.send(.captureRequested)
    await store.receive(\.captureFailed)
    #expect(accessRequests.value == 1)
    #expect(opened.value == [TasksFeature.screenSettingsURL.absoluteString])
    await store.send(.stop)
    await store.finish()
    #expect(posted.value == [TasksFeature.noAccessNotificationID, TasksFeature.noAccessNotificationID])
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
    await store.send(.deleteTapped(second.id)).finish()
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
    #expect(store.state.undoableID == task.id)
    #expect(store.state.visibleTasks(now: now.value, calendar: .current).isEmpty)
    await store.send(.undoTapped)
    #expect(store.state.tasks[id: task.id]?.isDone == false)
    await store.send(.doneTapped(task.id))
    await clock.advance(by: TasksFeature.undoTime)
    await store.receive(\.undoExpired)
    #expect(store.state.undoableID == nil)
    var filter = TaskFilter()
    filter.status = .done
    await store.send(.filterChanged(filter))
    #expect(store.state.visibleTasks(now: now.value, calendar: .current).map(\.id) == [task.id])
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
    await store.send(.screenTapped(task.id)).finish()
    #expect(opened.value == ["ru.keepcoder.Telegram", "screen.heic"])
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
