import ComposableArchitecture
import Foundation
import Testing
import VortexCore

@testable import VortexShell

extension FeatureDescriptor {
  static let music = FeatureDescriptor(id: "music", title: "Music", symbol: "music.note")
}

@MainActor
struct CatalogTests {
  let shell = ShellFeatureTests()

  /// Entering the catalog counts every feature as seen, but the ones that were new keep their badge for this visit.
  @Test
  func openingTheCatalogMarksEverythingSeenButKeepsTheBadgesForTheVisit() async {
    let store = shell.makeStore(features: [.timer, .music]) {
      $0.addedFeatures = ["timer"]
      $0.seenFeatures = ["timer"]
    }
    #expect(store.state.catalogDot)
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalog)) {
      $0.selectedTab = .catalog
      $0.openReason = .click
      $0.visitNew = ["music"]
      $0.settings.seenFeatures = ["timer", "music"]
    }
    #expect(!store.state.catalogDot)
    await shell.clock.advance(by: .milliseconds(400))
  }

  /// Leaving the catalog, by a tab or by closing the window, drops the badges: the next visit has nothing new.
  @Test
  func leavingTheCatalogDropsTheNewBadges() async {
    let store = shell.makeStore(features: [.timer, .music]) {
      $0.addedFeatures = ["timer"]
      $0.seenFeatures = ["timer"]
    }
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalog)) {
      $0.selectedTab = .catalog
      $0.openReason = .click
      $0.visitNew = ["music"]
      $0.settings.seenFeatures = ["timer", "music"]
    }
    await store.send(.tabSelected(.feature("timer"))) {
      $0.selectedTab = .feature("timer")
      $0.settings.lastTab = "feature:timer"
      $0.visitNew = []
    }
    await store.send(.tabSelected(.catalog)) { $0.selectedTab = .catalog }
    await store.send(.window(.escapePressed)) {
      $0.openReason = nil
      $0.selectedTab = .feature("timer")
    }
    await shell.clock.advance(by: .milliseconds(400))
  }

  // MARK: - Home

  /// "Add to Home" on a feature's page asks Home once, however often it is pressed.
  @Test
  func addToHomeAsksHomeOnce() async {
    let store = shell.makeStore()
    await store.send(.addToHomeTapped("shelf")) {
      $0.$homeAddRequests.withLock { $0 = ["shelf"] }
    }
    await store.send(.addToHomeTapped("shelf"))
  }

  /// An added feature's page offers "Add to Home" while none of its widgets is on Home, and says "On Home" once one is;
  /// a feature without widgets, or not added, has neither.
  @Test
  func thePageOffersAddToHomeUntilAWidgetIsOn() {
    var settings = ShellSettings()
    settings.addedFeatures = ["timer", "shelf", "tasks"]
    var state = ShellFeature.State(settings: settings, features: [.timer, .shelf, .tasks, .music], onboarding: .finished)
    state.homeWidgets = [
      HomeWidgetInfo(id: "shelf.files", feature: "shelf", place: .grid([.medium]), name: "Files", featureName: "Shelf", featureSymbol: "tray"),
      HomeWidgetInfo(id: "music.player", feature: "music", place: .grid([.wide]), name: "Player", featureName: "Music", featureSymbol: "music.note"),
    ]
    #expect(state.homeOnPage("shelf") == .canAdd)
    #expect(state.homeOnPage("tasks") == nil)
    #expect(state.homeOnPage("music") == nil)
    // Home found no room for it: the button stays, with the line under it.
    @Shared(.noRoomOnHome) var noRoom
    $noRoom.withLock { $0 = ["shelf"] }
    #expect(state.homeOnPage("shelf") == .noRoom)
    @Shared(.featuresOnHome) var onHome
    $onHome.withLock { $0 = ["shelf"] }
    #expect(state.homeOnPage("shelf") == .onHome)
  }

  /// "Add to Home" that found no room: the page says so until it is left, back to the list here; the button stays, so
  /// the user can try again.
  @Test
  func thePageSaysThereIsNoRoomUntilItIsLeft() async {
    let files = HomeWidgetInfo(
      id: "shelf.files", feature: "shelf", place: .grid([.medium]), name: "Files", featureName: "Shelf", featureSymbol: "tray"
    )
    let store = shell.makeStore { $0.seenFeatures = ["timer", "shelf", "tasks"] }
    await store.send(.homeWidgetsLoaded([files])) { $0.homeWidgets = [files] }
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalogPage("shelf"))) {
      $0.selectedTab = .catalogPage("shelf")
      $0.openReason = .click
    }
    await store.send(.addToHomeTapped("shelf")) { $0.$homeAddRequests.withLock { $0 = ["shelf"] } }
    // Home takes the request and finds no room.
    store.state.$homeAddRequests.withLock { $0 = [] }
    store.state.$noRoomOnHome.withLock { $0 = ["shelf"] }
    #expect(store.state.homeOnPage("shelf") == .noRoom)
    await store.send(.window(.escapePressed)) {
      $0.selectedTab = .catalog
      $0.$homeAddRequests.withLock { $0 = [] }
      $0.$noRoomOnHome.withLock { $0 = [] }
    }
    #expect(store.state.homeOnPage("shelf") == .canAdd)
  }

  /// Home hears of the running features' widgets from the shell, in sidebar order: at launch and whenever the running
  /// features or their order change, whether Home's tab shows or not.
  @Test
  func homeHearsOfTheRunningWidgetsInSidebarOrder() async {
    let timerWidget = HomeWidgetInfo(
      id: "timer.timer", feature: "timer", place: .notchRow, name: "Timer", featureName: "Timer", featureSymbol: "timer"
    )
    let shelfWidget = HomeWidgetInfo(
      id: "shelf.files", feature: "shelf", place: .grid([.medium, .wide]), name: "Files", featureName: "Shelf",
      featureSymbol: "tray"
    )
    let store = shell.makeStore()
    store.dependencies.featuresClient.homeWidgets = { ids in
      ids.flatMap { id in [timerWidget, shelfWidget].filter { $0.feature == id } }
    }
    await shell.launch(store, homeWidgets: [timerWidget, shelfWidget])
    @SharedReader(.runningHomeWidgets) var running
    #expect(running == [timerWidget, shelfWidget])
    await store.send(.featureDropped("shelf", onto: "timer")) {
      $0.settings.featureOrder = ["shelf", "timer", "tasks"]
    }
    await store.receive(\.homeWidgetsLoaded) { $0.homeWidgets = [shelfWidget, timerWidget] }
    #expect(running == [shelfWidget, timerWidget])
    await shell.clock.advance(by: .milliseconds(400))
  }

  /// The launch tells Home the running widgets even when none run, as in safe mode: Home then knows its widgets are
  /// away, rather than waiting to be told.
  @Test
  func theLaunchTellsHomeEvenThatNoWidgetRuns() async {
    let store = shell.makeStore(isSafeMode: true)
    @SharedReader(.runningHomeWidgets) var running
    #expect(running == nil)
    await shell.launch(store)
    #expect(running == [])
  }

  /// A feature stopped after a crash lights the catalog's dot until it runs again.
  @Test
  func aStoppedFeatureLightsTheDot() {
    var settings = ShellSettings()
    settings.addedFeatures = ["timer", "tasks"]
    settings.seenFeatures = ["timer", "tasks"]
    #expect(!ShellFeature.State(settings: settings, features: [.timer, .tasks]).catalogDot)
    settings.stoppedFeatures = ["tasks"]
    #expect(ShellFeature.State(settings: settings, features: [.timer, .tasks]).catalogDot)
  }

  /// In safe mode the features that wait light the dot; once all of them run it goes out.
  @Test
  func safeModeLightsTheDotWhileFeaturesWait() {
    var settings = ShellSettings()
    settings.addedFeatures = ["home", "timer"]
    settings.seenFeatures = ["home", "timer"]
    var state = ShellFeature.State(settings: settings, features: [.home, .timer], isSafeMode: true)
    #expect(state.catalogDot)
    state.safeModeStarted = ["timer"]
    #expect(!state.catalogDot)
  }

  /// A feature paused in this release is never new, so it lights nothing and gets no badge.
  @Test
  func pausedFeaturesAreNeverNew() async {
    let paused = FeatureDescriptor(id: "music", title: "Music", symbol: "music.note", suspension: "Broken on this macOS.")
    let store = shell.makeStore(features: [.timer, paused]) {
      $0.addedFeatures = ["timer"]
      $0.seenFeatures = ["timer"]
    }
    #expect(!store.state.catalogDot)
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalog)) {
      $0.selectedTab = .catalog
      $0.openReason = .click
      $0.settings.seenFeatures = ["timer", "music"]
    }
    await shell.clock.advance(by: .milliseconds(400))
  }

  /// The catalog leaves out built-in features; among those you can add the recommended ones come first.
  @Test
  func recommendedOnesComeFirstAmongThoseYouCanAdd() {
    var settings = ShellSettings()
    settings.addedFeatures = ["home", "timer"]
    let state = ShellFeature.State(settings: settings, features: [.home, .timer, .secrets, .music, .tasks])
    #expect(state.catalogFeatures.map(\.id) == ["timer", "secrets", "music", "tasks"])
    #expect(state.catalogAdded.map(\.id) == ["timer"])
    #expect(state.catalogAvailable.map(\.id) == ["tasks", "secrets", "music"])
  }

  // MARK: - A feature's page

  /// Add starts the feature on a trial, saved before it runs; its tab is the one the window opens on next, while the
  /// window stays on the page.
  @Test
  func addingStartsTheFeatureAsATrialAndRemembersItsTab() async {
    let store = shell.makeStore {
      $0.addedFeatures = ["timer", "shelf"]
      $0.seenFeatures = ["timer", "shelf", "tasks"]
    }
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalogPage("tasks"))) {
      $0.selectedTab = .catalogPage("tasks")
      $0.openReason = .click
    }
    await store.send(.featureAdded("tasks")) {
      $0.settings.addedFeatures = ["timer", "shelf", "tasks"]
      $0.settings.lastTab = "feature:tasks"
    }
    #expect(shell.saved.value.last?.addedFeatures == ["timer", "shelf", "tasks"])
    #expect(shell.trials.value == ["tasks"])
    await shell.clock.advance(by: .milliseconds(400))
    await store.finish()
    #expect(shell.featureSwitches.value == ["tasks:true"])
    #expect(store.state.pageState("tasks") == .added(needsSetup: false))
  }

  /// Remove stops the feature, leaves its tab and offers Undo for 5 s, which adds it back.
  @Test
  func removingStopsItLeavesItsTabAndOffersUndo() async {
    let store = shell.makeStore { $0.seenFeatures = ["timer", "shelf", "tasks"] }
    await shell.openByHover(store)
    #expect(store.state.selectedTab == .feature("timer"))
    await store.send(.featureRemoved("timer")) {
      $0.settings.addedFeatures = ["shelf", "tasks"]
      $0.selectedTab = .feature("shelf")
      $0.removedForUndo = "timer"
    }
    #expect(shell.saved.value.last?.addedFeatures == ["shelf", "tasks"])
    await store.send(.undoRemoveTapped) {
      $0.settings.addedFeatures = ["timer", "shelf", "tasks"]
      $0.settings.lastTab = "feature:timer"
      $0.removedForUndo = nil
    }
    await store.send(.featureRemoved("tasks")) {
      $0.settings.addedFeatures = ["timer", "shelf"]
      $0.removedForUndo = "tasks"
    }
    await shell.clock.advance(by: .seconds(5))
    await store.receive(\.undoExpired) { $0.removedForUndo = nil }
    await store.finish()
    #expect(shell.featureSwitches.value == ["timer:false", "timer:true", "tasks:false"])
    #expect(shell.trials.value == ["timer"])
  }

  /// Esc on a feature's page goes back to the list; on the list it closes the window.
  @Test
  func escapeOnAFeaturePageGoesBackToTheList() async {
    let store = shell.makeStore { $0.seenFeatures = ["timer", "shelf", "tasks"] }
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalogPage("tasks"))) {
      $0.selectedTab = .catalogPage("tasks")
      $0.openReason = .click
    }
    await store.send(.window(.escapePressed)) { $0.selectedTab = .catalog }
    await store.send(.window(.escapePressed)) {
      $0.openReason = nil
      $0.selectedTab = .feature("timer")
    }
    #expect(shell.dismissals.value == 1)
  }

  /// A feature whose own setup step isn't done shows it on its page.
  @Test
  func aFeatureWithAnUnfinishedStepShowsItOnThePage() {
    let keys = FeatureDescriptor(id: "secrets", title: "Keys", symbol: "key.horizontal", hasOnboardingStep: true)
    var settings = ShellSettings()
    settings.addedFeatures = ["timer", "secrets"]
    let state = ShellFeature.State(settings: settings, features: [.timer, keys, .shelf])
    #expect(state.pageState("secrets") == .added(needsSetup: true))
    #expect(state.pageState("timer") == .added(needsSetup: false))
    #expect(state.pageState("shelf") == .available)
    @Shared(.onboardingStepsDone) var stepsDone
    $stepsDone.withLock { $0 = ["secrets"] }
    #expect(state.pageState("secrets") == .added(needsSetup: false))
  }

  /// A feature's page shows its permissions as its settings page does once it is added: one that is off has the yellow
  /// mark and Turn on, one granted for the next launch "Works after restart" and Restart Vortex, one that works neither.
  /// Before it is added, none has a mark.
  @Test
  func thePageMarksItsPermissionsAsItsSettingsDoOnceAdded() {
    let tasks = FeatureDescriptor(
      id: "tasks",
      title: "Tasks",
      symbol: "checkmark.square",
      permissionNeeds: [
        PermissionNeed(.screenRecording, reason: "Reads the screen."),
        PermissionNeed(.notifications, reason: "Says when it's done."),
        PermissionNeed(.accessibility, reason: "Types for you."),
      ]
    )
    var settings = ShellSettings()
    settings.addedFeatures = ["timer"]
    var state = ShellFeature.State(settings: settings, features: [.timer, tasks], onboarding: .finished)
    state.$permissionStatuses.withLock {
      $0 = [.screenRecording: .notGranted, .notifications: .grantedAfterRestart, .accessibility: .granted]
    }
    #expect(state.permissionMark(.screenRecording, onPageOf: "tasks") == nil)
    state.setAdded("tasks", true)
    #expect(state.permissionMark(.screenRecording, onPageOf: "tasks") == .warning)
    #expect(state.permissionMark(.notifications, onPageOf: "tasks") == .afterRestart)
    #expect(state.permissionMark(.accessibility, onPageOf: "tasks") == nil)
    // Stopped after a crash, it is still added.
    state.settings.stoppedFeatures = ["tasks"]
    #expect(state.permissionMark(.screenRecording, onPageOf: "tasks") == .warning)
  }

  /// Files given to Vortex while no running feature takes them open the page of the one that would, and wait for it.
  @Test
  func filesNobodyTakesOpenTheShelfPage() async {
    let store = shell.makeStore {
      $0.addedFeatures = ["timer", "tasks"]
      $0.seenFeatures = ["timer", "shelf", "tasks"]
    }
    let file = URL(fileURLWithPath: "/tmp/a.ipa")
    await store.send(.filesReceived([file])) {
      $0.openReason = .hotkey
      $0.selectedTab = .catalogPage("shelf")
      $0.pendingFiles = [file]
    }
    #expect(shell.windowLog.value == ["size:large", "present:hotkey"])
    await store.send(.featureAdded("shelf")) {
      $0.settings.addedFeatures = ["timer", "shelf", "tasks"]
      $0.settings.lastTab = "feature:shelf"
      $0.pendingFiles = []
    }
    await shell.clock.advance(by: .milliseconds(400))
    await store.finish()
    #expect(shell.featureSwitches.value == ["shelf:true"])
    #expect(shell.receivedFiles.value == ["shelf:a.ipa"])
  }

  // MARK: - Erase Data

  /// Erase asks first, in the window, which stays open meanwhile and takes Esc as Cancel; confirmed, the feature is
  /// left to erase, saved at once, and Vortex restarts.
  @Test
  func confirmingEraseRemembersItAndRelaunches() async {
    let relaunches = LockIsolated(0)
    let store = shell.makeStore(features: [.timer, .shelf]) {
      $0.addedFeatures = ["timer"]
      $0.seenFeatures = ["timer", "shelf"]
    }
    store.dependencies.systemClient.relaunch = { relaunches.withValue { $0 += 1 } }
    await shell.openByHover(store)
    await store.send(.tabSelected(.catalogPage("shelf"))) {
      $0.selectedTab = .catalogPage("shelf")
      $0.openReason = .click
    }
    await store.send(.eraseTapped("timer"))
    await store.send(.eraseTapped("shelf")) { $0.eraseConfirmation = "shelf" }
    await store.send(.window(.clickedOutside))
    await store.send(.window(.escapePressed)) { $0.eraseConfirmation = nil }
    await store.send(.eraseTapped("shelf")) { $0.eraseConfirmation = "shelf" }
    await store.send(.eraseConfirmed) {
      $0.eraseConfirmation = nil
      $0.settings.pendingErase = ["shelf"]
    }
    #expect(shell.saved.value.last?.pendingErase == ["shelf"])
    await shell.clock.advance(by: .milliseconds(400))
    await store.finish()
    #expect(relaunches.value == 1)
    #expect(shell.dismissals.value == 0)
  }

  /// At launch each pending erase leaves the list, saved at once, before it runs, so a crash in it can't repeat; then
  /// it runs, and only then do features start. A feature added again meanwhile isn't erased.
  @Test
  func pendingErasesAreClearedBeforeTheyRunAndRunBeforeAnyFeature() async {
    let log = LockIsolated<[String]>([])
    let store = shell.makeStore(features: [.timer, .shelf]) {
      $0.addedFeatures = ["timer"]
      $0.seenFeatures = ["timer", "shelf"]
      $0.pendingErase = ["shelf", "timer"]
    }
    store.dependencies.settingsClient.save = { settings in log.withValue { $0.append("save:\(settings.pendingErase)") } }
    store.dependencies.featuresClient.eraseData = { id in log.withValue { $0.append("erase:\(id)") } }
    store.dependencies.featuresClient.setEnabled = { id, isEnabled in log.withValue { $0.append("\(id):\(isEnabled)") } }
    await shell.launch(store) { $0.settings.pendingErase = [] }
    await shell.clock.advance(by: .milliseconds(400))
    await store.finish()
    #expect(Array(log.value.prefix(3)) == ["save:[]", "erase:shelf", "timer:true"])
  }
}
