import AppKit
import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import VortexShell

extension FeatureDescriptor {
  static let timer = FeatureDescriptor(id: "timer", title: "Timer", symbol: "timer")
  static let shelf = FeatureDescriptor(id: "shelf", title: "Shelf", symbol: "tray", acceptsFileDrops: true)
  static let tasks = FeatureDescriptor(id: "tasks", title: "Tasks", symbol: "checkmark.square")
}

@MainActor
struct ShellFeatureTests {
  let clock = TestClock()
  let presented = LockIsolated<[OpenReason]>([])
  let dismissals = LockIsolated(0)
  let saved = LockIsolated<[ShellSettings]>([])
  let menuBarIcon = LockIsolated<[Bool]>([])
  let featureSwitches = LockIsolated<[String]>([])
  let receivedFiles = LockIsolated<[String]>([])
  let acceptsFiles = LockIsolated<[Bool]>([])
  let permissionReads = LockIsolated(0)

  func makeStore(
    features: [FeatureDescriptor] = [.timer, .shelf, .tasks],
    _ configure: (inout ShellSettings) -> Void = { _ in }
  ) -> TestStoreOf<ShellFeature> {
    var settings = ShellSettings()
    configure(&settings)
    return TestStore(initialState: ShellFeature.State(settings: settings, features: features)) {
      ShellFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.windowClient.present = { [presented] reason in presented.withValue { $0.append(reason) } }
      $0.windowClient.dismiss = { [dismissals] in dismissals.withValue { $0 += 1 } }
      $0.windowClient.setMenuBarIconVisible = { [menuBarIcon] isVisible in menuBarIcon.withValue { $0.append(isVisible) } }
      $0.settingsClient.save = { [saved] settings in saved.withValue { $0.append(settings) } }
      $0.featuresClient.setEnabled = { [featureSwitches] id, isEnabled in
        featureSwitches.withValue { $0.append("\(id):\(isEnabled)") }
      }
      $0.featuresClient.receiveFiles = { [receivedFiles] id, urls in
        receivedFiles.withValue { $0.append("\(id):\(urls.map(\.lastPathComponent).joined(separator: ","))") }
      }
      $0.windowClient.setAcceptsFiles = { [acceptsFiles] accepts in acceptsFiles.withValue { $0.append(accepts) } }
      $0.permissionsClient.refresh = { [permissionReads] in permissionReads.withValue { $0 += 1 } }
    }
  }

  /// Opens by hovering the notch for the default delay.
  func openByHover(_ store: TestStoreOf<ShellFeature>) async {
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .milliseconds(300))
    await store.receive(\.hoverDelayElapsed) { $0.openReason = .hover }
  }

  // MARK: - Opening

  @Test
  func hoverOpensAfterTheDelay() async {
    let store = makeStore()
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .milliseconds(299))
    #expect(presented.value.isEmpty)
    await clock.advance(by: .milliseconds(1))
    await store.receive(\.hoverDelayElapsed) { $0.openReason = .hover }
    #expect(presented.value == [.hover])
  }

  @Test
  func leavingTheNotchBeforeTheDelayCancels() async {
    let store = makeStore()
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .milliseconds(200))
    await store.send(.window(.notchHoverChanged(isInside: false)))
    await clock.advance(by: .seconds(1))
    #expect(presented.value.isEmpty)
  }

  @Test
  func hoverDoesNothingWhenTurnedOff() async {
    let store = makeStore { $0.openOnHover = false }
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .seconds(3))
    #expect(presented.value.isEmpty)
  }

  @Test
  func clickOpensAtOnceAndClosesOnSecondClick() async {
    let store = makeStore()
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = .click }
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = nil }
    #expect(presented.value == [.click])
    #expect(dismissals.value == 1)
  }

  @Test
  func clickDoesNothingWhenTurnedOff() async {
    let store = makeStore { $0.openOnClick = false }
    await store.send(.window(.notchClicked(feature: nil)))
    #expect(presented.value.isEmpty)
  }

  /// Notifications send no signal when they change, and the window opening activates no app (S47).
  @Test
  func everyOpeningReadsThePermissionsAgainClosingDoesNot() async {
    let store = makeStore()
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = .click }
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = nil }
    await store.send(.window(.menuBarIconClicked)) { $0.openReason = .menuBarIcon }
    await store.finish()
    #expect(permissionReads.value == 2)
  }

  @Test
  func clickKeepsAWindowOpenedByHoverOpen() async {
    let store = makeStore()
    await openByHover(store)
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = .click }
    await store.send(.window(.pointerInsideWindowChanged(isInside: false)))
    await clock.advance(by: .seconds(3))
    #expect(dismissals.value == 0)
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = nil }
  }

  @Test
  func clickingAnEarOpensItsFeatureWithoutChangingTheRememberedTab() async {
    let store = makeStore { $0.lastTab = "feature:tasks" }
    await store.send(.window(.notchClicked(feature: "timer"))) {
      $0.openReason = .click
      $0.selectedTab = .feature("timer")
    }
    #expect(store.state.settings.lastTab == "feature:tasks")
  }

  @Test
  func clickingTheEarOfAFeatureThatIsOffOpensTheLastTab() async {
    let store = makeStore {
      $0.lastTab = "feature:tasks"
      $0.disabledFeatures = ["timer"]
    }
    await store.send(.window(.notchClicked(feature: "timer"))) {
      $0.openReason = .click
    }
    #expect(store.state.selectedTab == .feature("tasks"))
  }

  @Test
  func hoveringAnEarOpensItsFeatureWithoutChangingTheRememberedTab() async {
    let store = makeStore { $0.lastTab = "feature:tasks" }
    // The window controller reports the ear as the pointer comes in, before the hover itself.
    await store.send(.window(.notchPointerOver(feature: "timer"))) { $0.hoveredEar = "timer" }
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .milliseconds(299))
    #expect(presented.value.isEmpty)
    await clock.advance(by: .milliseconds(1))
    await store.receive(\.hoverDelayElapsed) {
      $0.openReason = .hover
      $0.selectedTab = .feature("timer")
    }
    #expect(store.state.settings.lastTab == "feature:tasks")
    #expect(presented.value == [.hover])
  }

  @Test
  func hoveringTheCutoutOpensTheLastTab() async {
    let store = makeStore { $0.lastTab = "feature:tasks" }
    await store.send(.window(.notchPointerOver(feature: nil)))
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .milliseconds(300))
    await store.receive(\.hoverDelayElapsed) { $0.openReason = .hover }
    #expect(store.state.selectedTab == .feature("tasks"))
  }

  @Test
  func movingFromAnEarOntoTheCutoutBeforeTheDelayOpensTheLastTab() async {
    let store = makeStore { $0.lastTab = "feature:tasks" }
    await store.send(.window(.notchPointerOver(feature: "timer"))) { $0.hoveredEar = "timer" }
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .milliseconds(200))
    await store.send(.window(.notchPointerOver(feature: nil))) { $0.hoveredEar = nil }
    await clock.advance(by: .milliseconds(100))
    await store.receive(\.hoverDelayElapsed) { $0.openReason = .hover }
    #expect(store.state.selectedTab == .feature("tasks"))
  }

  @Test
  func movingOntoAnEarBeforeTheDelayOpensItsFeatureWithoutRestartingTheDelay() async {
    let store = makeStore { $0.lastTab = "feature:tasks" }
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .milliseconds(200))
    await store.send(.window(.notchPointerOver(feature: "shelf"))) { $0.hoveredEar = "shelf" }
    await clock.advance(by: .milliseconds(100))
    await store.receive(\.hoverDelayElapsed) {
      $0.openReason = .hover
      $0.selectedTab = .feature("shelf")
    }
    #expect(store.state.settings.lastTab == "feature:tasks")
  }

  /// A feature that is off ("timer"), and one that has no tab at all ("gone").
  @Test(arguments: ["timer", "gone"])
  func hoveringTheEarOfAFeatureWithoutATabOpensTheLastTab(ear: FeatureID) async {
    let store = makeStore {
      $0.lastTab = "feature:tasks"
      $0.disabledFeatures = ["timer"]
    }
    await store.send(.window(.notchPointerOver(feature: ear))) { $0.hoveredEar = ear }
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .milliseconds(300))
    await store.receive(\.hoverDelayElapsed) { $0.openReason = .hover }
    #expect(store.state.selectedTab == .feature("tasks"))
  }

  @Test
  func leavingTheNotchForgetsTheEar() async {
    let store = makeStore { $0.lastTab = "feature:tasks" }
    // A click on the timer's ear showed its tab, and the pointer then rested on that ear.
    await store.send(.window(.notchClicked(feature: "timer"))) {
      $0.openReason = .click
      $0.selectedTab = .feature("timer")
    }
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = nil }
    await store.send(.window(.notchPointerOver(feature: "timer"))) { $0.hoveredEar = "timer" }
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .milliseconds(100))
    await store.send(.window(.notchHoverChanged(isInside: false))) { $0.hoveredEar = nil }
    // Back in over the cutout, which reports no ear: the last tab, not the timer's.
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .milliseconds(300))
    await store.receive(\.hoverDelayElapsed) {
      $0.openReason = .hover
      $0.selectedTab = .feature("tasks")
    }
  }

  @Test
  func theEarUnderThePointerOnlyMattersToHoverAndClick() async {
    let store = makeStore { $0.lastTab = "feature:tasks" }
    await store.send(.window(.notchPointerOver(feature: "timer"))) { $0.hoveredEar = "timer" }
    await store.send(.openHotkeyPressed) { $0.openReason = .hotkey }
    #expect(store.state.selectedTab == .feature("tasks"))
  }

  @Test
  func hotkeyAndMenuBarIconToggle() async {
    let store = makeStore()
    await store.send(.openHotkeyPressed) { $0.openReason = .hotkey }
    await store.send(.window(.menuBarIconClicked)) { $0.openReason = nil }
    await store.send(.window(.menuBarIconClicked)) { $0.openReason = .menuBarIcon }
    #expect(presented.value == [.hotkey, .menuBarIcon])
  }

  @Test
  func featureShortcutsOpenTheirTab() async {
    let store = makeStore()
    await store.send(.featureHotkeyPressed("tasks")) {
      $0.openReason = .hotkey
      $0.selectedTab = .feature("tasks")
      $0.settings.lastTab = "feature:tasks"
    }
    await store.send(.featureHotkeyPressed("shelf")) {
      $0.selectedTab = .feature("shelf")
      $0.settings.lastTab = "feature:shelf"
    }
    await store.send(.featureHotkeyPressed("shelf")) { $0.openReason = nil }
    await store.send(.featureEnabledChanged("timer", isEnabled: false)) { $0.settings.disabledFeatures = ["timer"] }
    await store.send(.featureHotkeyPressed("timer"))
    await clock.advance(by: .milliseconds(400))
    await store.finish()
    #expect(presented.value == [.hotkey])
  }

  // MARK: - Closing

  @Test
  func pointerLeavingClosesAWindowOpenedByHover() async {
    let store = makeStore()
    await openByHover(store)
    await store.send(.window(.pointerInsideWindowChanged(isInside: true))) { $0.isPointerInsideWindow = true }
    await store.send(.window(.pointerInsideWindowChanged(isInside: false))) { $0.isPointerInsideWindow = false }
    await clock.advance(by: .milliseconds(300))
    // Coming back in time keeps the window open.
    await store.send(.window(.pointerInsideWindowChanged(isInside: true))) { $0.isPointerInsideWindow = true }
    await clock.advance(by: .seconds(2))
    await store.send(.window(.pointerInsideWindowChanged(isInside: false))) { $0.isPointerInsideWindow = false }
    await clock.advance(by: .milliseconds(500))
    await store.receive(\.pointerLeaveDelayElapsed) { $0.openReason = nil }
    #expect(dismissals.value == 1)
  }

  @Test
  func pointerLeavingDoesNotCloseAWindowOpenedOnPurpose() async {
    let store = makeStore()
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = .click }
    await store.send(.window(.pointerInsideWindowChanged(isInside: true))) { $0.isPointerInsideWindow = true }
    await store.send(.window(.pointerInsideWindowChanged(isInside: false))) { $0.isPointerInsideWindow = false }
    await clock.advance(by: .seconds(3))
    #expect(dismissals.value == 0)
  }

  @Test
  func pointerLeavingDoesNothingWhenTurnedOff() async {
    let store = makeStore { $0.closeOnPointerLeave = false }
    await openByHover(store)
    await store.send(.window(.pointerInsideWindowChanged(isInside: true))) { $0.isPointerInsideWindow = true }
    await store.send(.window(.pointerInsideWindowChanged(isInside: false))) { $0.isPointerInsideWindow = false }
    await clock.advance(by: .seconds(3))
    #expect(dismissals.value == 0)
  }

  @Test
  func clickOutsideCloses() async {
    let store = makeStore()
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = .click }
    await store.send(.window(.clickedOutside)) { $0.openReason = nil }
  }

  @Test
  func clickOutsideDoesNothingWhenTurnedOff() async {
    let store = makeStore { $0.closeOnClickOutside = false }
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = .click }
    await store.send(.window(.clickedOutside))
    #expect(dismissals.value == 0)
  }

  @Test
  func escapeAlwaysCloses() async {
    let store = makeStore {
      $0.closeOnClickOutside = false
      $0.closeOnPointerLeave = false
    }
    await store.send(.window(.escapePressed))
    await store.send(.openHotkeyPressed) { $0.openReason = .hotkey }
    await store.send(.window(.escapePressed)) { $0.openReason = nil }
    #expect(dismissals.value == 1)
  }

  @Test
  func screenChangesCloseTheWindow() async {
    let store = makeStore()
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = .click }
    await store.send(.window(.screensChanged(everyScreenHasNotch: true))) { $0.openReason = nil }
    #expect(dismissals.value == 1)
  }

  @Test
  func activityOutsideKeepsTheWindowOpenUntilItEnds() async {
    let store = makeStore()
    await openByHover(store)
    await store.send(.window(.pointerInsideWindowChanged(isInside: true))) { $0.isPointerInsideWindow = true }
    await store.send(.window(.outsideActivityChanged(isActive: true))) { $0.isHeldOpen = true }
    await store.send(.window(.pointerInsideWindowChanged(isInside: false))) { $0.isPointerInsideWindow = false }
    await store.send(.window(.clickedOutside))
    await clock.advance(by: .seconds(3))
    #expect(dismissals.value == 0)

    // Dropped in another app, or Quick Look closed: the usual leave delay starts.
    await store.send(.window(.outsideActivityChanged(isActive: false))) { $0.isHeldOpen = false }
    await store.send(.window(.pointerInsideWindowChanged(isInside: false)))
    await clock.advance(by: .milliseconds(500))
    await store.receive(\.pointerLeaveDelayElapsed) { $0.openReason = nil }
  }

  // MARK: - Keyboard cleaning

  @Test
  func keyboardCleaningKeepsTheWindowOpenUntilTheKeyboardIsBackOnThenClosesIt() async {
    let holds = LockIsolated<[Bool]>([])
    let locks = LockIsolated<[Bool]>([])
    let store = makeStore()
    store.dependencies.keyboardLockClient.hasAccess = { true }
    store.dependencies.keyboardLockClient.lock = { locks.withValue { $0.append(true) }; return true }
    store.dependencies.keyboardLockClient.unlock = { locks.withValue { $0.append(false) } }
    store.dependencies.windowClient.holdKeyboard = { isHeld in holds.withValue { $0.append(isHeld) } }
    await openByHover(store)
    await store.send(.keyboardCleaning(.startTapped)) { $0.keyboardCleaning.isLocked = true }

    // Nothing the window would usually close on closes it; new screens move it there.
    await store.send(.window(.pointerInsideWindowChanged(isInside: true))) { $0.isPointerInsideWindow = true }
    await store.send(.window(.pointerInsideWindowChanged(isInside: false))) { $0.isPointerInsideWindow = false }
    await clock.advance(by: .seconds(3))
    await store.receive(\.pointerLeaveDelayElapsed)
    await store.send(.window(.clickedOutside))
    await store.send(.window(.escapePressed))
    await store.send(.window(.menuBarIconClicked))
    await store.send(.openHotkeyPressed)
    await store.send(.window(.screensChanged(everyScreenHasNotch: true)))
    await store.finish()
    #expect(dismissals.value == 0)
    #expect(presented.value == [.hover, .hover])
    #expect(locks.value == [true])
    #expect(holds.value == [true])

    // Back on: the keys go back to the app the user was in, and the window closes.
    await store.send(.keyboardCleaning(.stopTapped)) {
      $0.keyboardCleaning.isLocked = false
      $0.openReason = nil
    }
    await store.finish()
    #expect(locks.value == [true, false])
    #expect(holds.value == [true, false])
    #expect(dismissals.value == 1)
  }

  // MARK: - Files dragged to the notch

  @Test
  func filesOpenTheFeatureThatTakesThemAndCloseWhenThePointerLeaves() async {
    let store = makeStore { $0.lastTab = "feature:tasks" }
    #expect(store.state.selectedTab == .feature("tasks"))
    await store.send(.window(.fileDragEnteredNotch)) {
      $0.openReason = .fileDrag
      $0.selectedTab = .feature("shelf")
    }
    #expect(store.state.settings.lastTab == "feature:tasks")
    await store.send(.window(.pointerInsideWindowChanged(isInside: false)))
    await clock.advance(by: .milliseconds(500))
    await store.receive(\.pointerLeaveDelayElapsed) { $0.openReason = nil }
  }

  @Test
  func filesAreIgnoredWhileNoFeatureTakesThem() async {
    let store = makeStore(features: [.timer, .tasks])
    await store.send(.window(.fileDragEnteredNotch))
    await store.send(.window(.filesDroppedOnMenuBarIcon([URL(fileURLWithPath: "/tmp/a.ipa")])))
    await store.send(.filesReceived([URL(fileURLWithPath: "/tmp/a.ipa")]))
    await store.finish()
    #expect(presented.value.isEmpty)
    #expect(receivedFiles.value.isEmpty)
  }

  @Test
  func filesDroppedOnTheIconOrOpenedGoToTheFeatureWithoutOpeningTheWindow() async {
    let store = makeStore()
    await store.send(.window(.filesDroppedOnMenuBarIcon([URL(fileURLWithPath: "/tmp/a.ipa"), URL(fileURLWithPath: "/tmp/b.apk")])))
    await store.send(.filesReceived([URL(fileURLWithPath: "/tmp/c.dmg")]))
    await store.finish()
    #expect(receivedFiles.value == ["shelf:a.ipa,b.apk", "shelf:c.dmg"])
    #expect(presented.value.isEmpty)
  }

  @Test
  func theIconTakesFilesOnlyWhileAFeatureDoes() async {
    let store = makeStore()
    await store.send(.featureEnabledChanged("shelf", isEnabled: false)) { $0.settings.disabledFeatures = ["shelf"] }
    await store.send(.featureEnabledChanged("shelf", isEnabled: true)) { $0.settings.disabledFeatures = [] }
    await clock.advance(by: .milliseconds(400))
    await store.finish()
    #expect(acceptsFiles.value == [false, true])
  }

  // MARK: - Tabs and features

  @Test
  func startsOnTheFirstFeatureThenRemembersTheLastTab() async {
    let store = makeStore()
    #expect(store.state.selectedTab == .feature("timer"))
    await store.send(.tabSelected(.feature("tasks"))) {
      $0.selectedTab = .feature("tasks")
      $0.settings.lastTab = "feature:tasks"
    }
    await clock.advance(by: .milliseconds(400))
    #expect(saved.value.last?.lastTab == "feature:tasks")

    let reopened = ShellFeature.State(settings: saved.value.last!, features: [.timer, .shelf, .tasks])
    #expect(reopened.selectedTab == .feature("tasks"))
  }

  @Test
  func settingsTabWithoutAnyFeatures() {
    let state = ShellFeature.State(features: [])
    #expect(state.selectedTab == .settings)
    #expect(state.sidebarFeatures.isEmpty)
  }

  @Test
  func turningAFeatureOffRemovesItAndStopsIt() async {
    let store = makeStore()
    await store.send(.featureEnabledChanged("timer", isEnabled: false)) {
      $0.settings.disabledFeatures = ["timer"]
      $0.selectedTab = .feature("shelf")
    }
    #expect(store.state.sidebarFeatures.map(\.id) == ["shelf", "tasks"])
    await store.send(.featureEnabledChanged("timer", isEnabled: true)) {
      $0.settings.disabledFeatures = []
    }
    await clock.advance(by: .milliseconds(400))
    await store.finish()
    #expect(featureSwitches.value == ["timer:false", "timer:true"])
  }

  @Test
  func featuresAreReorderedByDragging() async {
    let store = makeStore()
    await store.send(.featureDropped("tasks", onto: "timer")) {
      $0.settings.featureOrder = ["tasks", "timer", "shelf"]
    }
    await store.send(.featureDropped("tasks", onto: "shelf")) {
      $0.settings.featureOrder = ["timer", "shelf", "tasks"]
    }
    await store.send(.featureDropped("tasks", onto: "tasks"))
    await store.send(.featureDropped("unknown", onto: "timer"))
    #expect(store.state.sidebarFeatures.map(\.id) == ["timer", "shelf", "tasks"])
    await clock.advance(by: .milliseconds(400))
  }

  @Test
  func unknownFeaturesInTheSavedOrderAreIgnored() {
    var settings = ShellSettings()
    settings.featureOrder = ["gone", "tasks"]
    let state = ShellFeature.State(settings: settings, features: [.timer, .shelf, .tasks])
    #expect(state.orderedFeatures.map(\.id) == ["tasks", "timer", "shelf"])
  }

  // MARK: - Settings and system

  @Test
  func settingsAreSavedAfterAPause() async {
    let store = makeStore()
    await store.send(.binding(.set(\.settings.hoverDelay, 1.0))) { $0.settings.hoverDelay = 1.0 }
    await clock.advance(by: .milliseconds(200))
    await store.send(.binding(.set(\.settings.hoverDelay, 1.2))) { $0.settings.hoverDelay = 1.2 }
    await clock.advance(by: .milliseconds(400))
    #expect(saved.value.map(\.hoverDelay) == [1.2])
  }

  @Test
  func menuBarIconStaysOnWhileADisplayHasNoNotch() async {
    let store = makeStore { $0.showMenuBarIcon = false }
    await store.send(.window(.screensChanged(everyScreenHasNotch: false))) { $0.everyScreenHasNotch = false }
    await store.send(.window(.screensChanged(everyScreenHasNotch: true))) { $0.everyScreenHasNotch = true }
    await store.finish()
    #expect(menuBarIcon.value == [true, false])
  }

  @Test
  func menuBarIconStaysOnWhileTheNotchCannotOpenVortex() async {
    let store = makeStore { $0.showMenuBarIcon = false }
    await store.send(.binding(.set(\.settings.openOnHover, false))) { $0.settings.openOnHover = false }
    await store.send(.binding(.set(\.settings.openOnClick, false))) { $0.settings.openOnClick = false }
    #expect(store.state.isMenuBarIconRequired)
    await clock.advance(by: .milliseconds(400))
    await store.finish()
    #expect(menuBarIcon.value == [true])
  }

  @Test
  func languageChangeAsksForARestart() async {
    let applied = LockIsolated<[AppLanguage]>([])
    let store = makeStore()
    store.dependencies.systemClient.setLanguage = { language in applied.withValue { $0.append(language) } }
    await store.send(.binding(.set(\.language, .english))) { $0.language = .english }
    #expect(store.state.needsRestartForLanguage)
    await store.finish()
    #expect(applied.value == [.english])
  }

  @Test
  func launchStartsFeaturesAndSetsUpTheShell() async {
    let firstLaunchSetUps = LockIsolated(0)
    let store = makeStore { $0.disabledFeatures = ["tasks"] }
    store.dependencies.windowClient.events = { .finished }
    store.dependencies.hotkeyClient.presses = { _ in .finished }
    store.dependencies.systemClient.applyTheme = { _ in }
    store.dependencies.launchAtLoginClient.enableOnFirstLaunch = { firstLaunchSetUps.withValue { $0 += 1 } }
    store.dependencies.launchAtLoginClient.status = { .enabled }
    store.dependencies.permissionsClient.updates = { .finished }
    store.dependencies.permissionPage.requests = { .finished }

    await store.send(.task)
    await store.receive(\.launchAtLoginStatusLoaded) { $0.launchAtLogin = .enabled }
    await store.finish()
    #expect(menuBarIcon.value == [true])
    #expect(featureSwitches.value == ["timer:true", "shelf:true", "tasks:false"])
    #expect(firstLaunchSetUps.value == 1)
  }

  @Test
  func launchAtLoginShowsWhatTheSystemDecided() async {
    let store = makeStore()
    store.dependencies.launchAtLoginClient.setEnabled = { _ in .requiresApproval }
    await store.send(.launchAtLoginChanged(true))
    await store.receive(\.launchAtLoginStatusLoaded) { $0.launchAtLogin = .requiresApproval }
  }

  @Test
  func theMenuBarIconWindowCanHandDropsToTheController() {
    // The icon's window forwards drags only to a delegate that answers these selectors.
    let controller = WindowController.shared
    #expect(controller.responds(to: #selector(NSDraggingDestination.draggingEntered(_:))))
    #expect(controller.responds(to: #selector(NSDraggingDestination.draggingExited(_:))))
    #expect(controller.responds(to: #selector(NSDraggingDestination.performDragOperation(_:))))
  }

  // MARK: - The notch's hit view

  /// A pointer event at `x`, as a tracking area sends it to the view.
  func pointerEvent(_ type: NSEvent.EventType, x: CGFloat) throws -> NSEvent {
    let location = NSPoint(x: x, y: 10)
    let event = switch type {
    case .mouseEntered, .mouseExited:
      NSEvent.enterExitEvent(
        with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        eventNumber: 0, trackingNumber: 0, userData: nil
      )
    default:
      NSEvent.mouseEvent(
        with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        eventNumber: 0, clickCount: 0, pressure: 0
      )
    }
    return try #require(event)
  }

  @Test
  func theNotchReportsWhereThePointerComesInAndMoves() throws {
    let hit = NotchHitView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
    var log: [String] = []
    hit.onPointerMoved = { log.append("at \(Int($0.x))") }
    hit.onHoverChanged = { log.append($0 ? "in" : "out") }
    hit.mouseEntered(with: try pointerEvent(.mouseEntered, x: 30))
    hit.mouseMoved(with: try pointerEvent(.mouseMoved, x: 150))
    hit.mouseExited(with: try pointerEvent(.mouseExited, x: 150))
    // The point goes before the hover, so the shell knows the ear when the hover starts.
    #expect(log == ["at 30", "in", "at 150", "out"])
  }

  @Test
  func theNotchSaysNothingWhileHoverIsSuppressedUntilThePointerLeaves() throws {
    let hit = NotchHitView(frame: NSRect(x: 0, y: 0, width: 300, height: 32))
    var log: [String] = []
    hit.onPointerMoved = { log.append("at \(Int($0.x))") }
    hit.onHoverChanged = { log.append($0 ? "in" : "out") }
    // The window closed under the pointer: whatever the pointer does on the notch must not open it again.
    hit.suppressHoverUntilPointerLeaves()
    hit.mouseEntered(with: try pointerEvent(.mouseEntered, x: 30))
    hit.mouseMoved(with: try pointerEvent(.mouseMoved, x: 150))
    #expect(log.isEmpty)
    hit.mouseExited(with: try pointerEvent(.mouseExited, x: 150))
    hit.mouseEntered(with: try pointerEvent(.mouseEntered, x: 270))
    hit.mouseMoved(with: try pointerEvent(.mouseMoved, x: 280))
    #expect(log == ["out", "at 270", "in", "at 280"])
  }

  @Test
  func onlyTheNotchAsksForMouseMoves() {
    #expect(NotchHitView().trackingOptions.contains(.mouseMoved))
    #expect(NotchHitView().trackingOptions.contains(.mouseEnteredAndExited))
    // The window's own tracking view needs no stream of moves.
    #expect(!HoverTrackingView().trackingOptions.contains(.mouseMoved))
  }
}
