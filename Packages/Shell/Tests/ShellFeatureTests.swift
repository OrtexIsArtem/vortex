import AppKit
import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import VortexShell

extension FeatureDescriptor {
  static let home = FeatureDescriptor(id: "home", title: "Home", symbol: "square.grid.2x2", isBuiltIn: true)
  static let timer = FeatureDescriptor(id: "timer", title: "Timer", symbol: "timer", isRecommended: true)
  static let shelf = FeatureDescriptor(
    id: "shelf", title: "Shelf", symbol: "tray", acceptsFileDrops: true, isRecommended: true
  )
  static let tasks = FeatureDescriptor(id: "tasks", title: "Tasks", symbol: "checkmark.square", isRecommended: true)
  static let secrets = FeatureDescriptor(id: "secrets", title: "Keys", symbol: "key.horizontal")
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
  let hiddenIndicatorOwners = LockIsolated<[Set<FeatureID>]>([])
  let trials = LockIsolated<[FeatureID]>([])
  /// The window's sizes and opens, in order.
  let windowLog = LockIsolated<[String]>([])

  func makeStore(
    features: [FeatureDescriptor] = [.timer, .shelf, .tasks],
    isSafeMode: Bool = false,
    _ configure: (inout ShellSettings) -> Void = { _ in }
  ) -> TestStoreOf<ShellFeature> {
    var settings = ShellSettings()
    configure(&settings)
    // The onboarding is done here; OnboardingFeatureTests and ShellOnboardingTests cover it.
    let state = ShellFeature.State(settings: settings, features: features, onboarding: .finished, isSafeMode: isSafeMode)
    return TestStore(initialState: state) {
      ShellFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.windowClient.present = { [presented, windowLog] reason in
        presented.withValue { $0.append(reason) }
        windowLog.withValue { $0.append("present:\(reason)") }
      }
      $0.windowClient.setSize = { [windowLog] size in windowLog.withValue { $0.append("size:\(size)") } }
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
      $0.windowClient.setHiddenIndicatorOwners = { [hiddenIndicatorOwners] owners in
        hiddenIndicatorOwners.withValue { $0.append(owners) }
      }
      $0.hotkeyClient.presses = { _ in .finished }
      $0.launchGuard.beginTrial = { [trials] id in trials.withValue { $0.append(id) } }
    }
  }

  /// Sends the launch's `.task` with every system listener ending at once, and waits until the shell has started.
  /// `change`: what the launch itself changes in the state.
  @discardableResult
  func launch(
    _ store: TestStoreOf<ShellFeature>,
    _ change: ((inout ShellFeature.State) -> Void)? = nil
  ) async -> TestStoreTask {
    let names = SystemSettingsNames(privacyAndSecurity: "Privacy & Security", accessibility: "Accessibility")
    store.dependencies.windowClient.events = { .finished }
    store.dependencies.systemClient.applyTheme = { _ in }
    store.dependencies.launchAtLoginClient.status = { .disabled }
    store.dependencies.permissionsClient.updates = { .finished }
    store.dependencies.permissionPage.requests = { .finished }
    store.dependencies.activeAppClient.activations = { .finished }
    store.dependencies.activeAppClient.terminations = { .finished }
    store.dependencies.systemSettingsNamesClient.names = { names }
    let task = await store.send(.task, assert: change)
    await store.receive(\.launchAtLoginStatusLoaded)
    await store.receive(\.onboarding.systemSettingsNamesLoaded) { $0.onboarding.settingsNames = names }
    await store.receive(\.started) { $0.isStarted = true }
    return task
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

  /// Notifications send no signal when they change, and the window opening activates no app.
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
      $0.addedFeatures = ["shelf", "tasks"]
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
      $0.addedFeatures = ["shelf", "tasks"]
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
    await store.send(.featureRemoved("timer")) {
      $0.settings.addedFeatures = ["shelf", "tasks"]
      $0.removedForUndo = "timer"
    }
    await store.send(.featureHotkeyPressed("timer"))
    await clock.advance(by: .seconds(5))
    await store.receive(\.undoExpired) { $0.removedForUndo = nil }
    await store.finish()
    #expect(presented.value == [.hotkey])
  }

  // MARK: - The catalog's large window

  /// Going to the catalog grows the window and counts as a deliberate open: a window opened on the way past stays open
  /// when the pointer leaves it. The catalog isn't remembered as the last tab.
  @Test
  func theCatalogOpensLargeAndCountsAsADeliberateOpen() async {
    let store = makeStore { $0.lastTab = "feature:tasks" }
    await openByHover(store)
    await store.send(.tabSelected(.catalog)) {
      $0.selectedTab = .catalog
      $0.openReason = .click
    }
    await store.send(.window(.pointerInsideWindowChanged(isInside: false)))
    await clock.advance(by: .seconds(5))
    #expect(windowLog.value == ["size:regular", "present:hover", "size:large"])
    #expect(store.state.settings.lastTab == "feature:tasks")
    #expect(dismissals.value == 0)
  }

  /// "About" in a sidebar icon's menu opens the feature's page in the catalog, in the large window.
  @Test
  func aboutFromTheSidebarOpensTheFeaturePageLarge() async {
    let store = makeStore()
    await openByHover(store)
    await store.send(.tabSelected(.catalogPage("timer"))) {
      $0.selectedTab = .catalogPage("timer")
      $0.openReason = .click
    }
    #expect(store.state.windowSize == .large)
    #expect(windowLog.value == ["size:regular", "present:hover", "size:large"])
  }

  /// Every open starts at the regular size on an ordinary tab, even after settings that remember the catalog.
  @Test
  func openingAlwaysStartsRegularOnAnOrdinaryTab() async {
    let store = makeStore { $0.lastTab = "catalog" }
    #expect(store.state.selectedTab == .feature("timer"))
    await openByHover(store)
    #expect(store.state.selectedTab == .feature("timer"))
    #expect(windowLog.value == ["size:regular", "present:hover"])
  }

  /// Closing leaves the catalog: the next open shows the last ordinary tab.
  @Test
  func closingLeavesTheCatalog() async {
    let store = makeStore { $0.lastTab = "feature:shelf" }
    await openByHover(store)
    await store.send(.tabSelected(.catalog)) {
      $0.selectedTab = .catalog
      $0.openReason = .click
    }
    await store.send(.window(.escapePressed)) {
      $0.openReason = nil
      $0.selectedTab = .feature("shelf")
    }
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
    store.dependencies.keyboardLockClient.lock = { locks.withValue { $0.append(true) }; return true }
    store.dependencies.keyboardLockClient.unlock = { locks.withValue { $0.append(false) } }
    store.dependencies.keyboardLockClient.layout = { .ansi }
    store.dependencies.keyboardLockClient.presses = { .finished }
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

  /// A key that got past the lock and went down in Vortex's window washes its key too; after the lock, nothing does.
  @Test
  func aKeyThatReachesTheWindowDuringTheLockWashesItsKey() async {
    let store = makeStore()
    store.dependencies.keyboardLockClient.lock = { true }
    store.dependencies.keyboardLockClient.unlock = {}
    store.dependencies.keyboardLockClient.layout = { .iso }
    store.dependencies.keyboardLockClient.presses = { .finished }
    store.dependencies.windowClient.holdKeyboard = { _ in }
    await openByHover(store)
    await store.send(.keyboardCleaning(.startTapped)) {
      $0.keyboardCleaning.isLocked = true
      $0.keyboardCleaning.layout = .iso
    }
    await store.send(.window(.keyPressedWhileHeld(.q)))
    await store.receive(\.keyboardCleaning.keyPressed, .q) { $0.keyboardCleaning.presses[.q] = 1 }
    await store.send(.keyboardCleaning(.stopTapped)) {
      $0.keyboardCleaning.isLocked = false
      $0.keyboardCleaning.presses = [:]
      $0.openReason = nil
    }
    await store.send(.window(.keyPressedWhileHeld(.q)))
    await store.receive(\.keyboardCleaning.keyPressed, .q)
    await store.finish()
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
    await store.send(.featureRemoved("shelf")) {
      $0.settings.addedFeatures = ["timer", "tasks"]
      $0.removedForUndo = "shelf"
    }
    await store.send(.featureAdded("shelf")) {
      $0.settings.addedFeatures = ["timer", "shelf", "tasks"]
      $0.settings.lastTab = "feature:shelf"
      $0.removedForUndo = nil
    }
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
  func removingAFeatureStopsItAndLeavesItsTab() async {
    let store = makeStore()
    await store.send(.featureRemoved("timer")) {
      $0.settings.addedFeatures = ["shelf", "tasks"]
      $0.selectedTab = .feature("shelf")
      $0.removedForUndo = "timer"
    }
    #expect(store.state.sidebarFeatures.map(\.id) == ["shelf", "tasks"])
    await store.send(.featureAdded("timer")) {
      $0.settings.addedFeatures = ["timer", "shelf", "tasks"]
      $0.settings.lastTab = "feature:timer"
      $0.removedForUndo = nil
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
    // Done's hint follows the screens too: the icon shows, and the notch display is still a way in.
    await store.send(.window(.screensChanged(everyScreenHasNotch: false))) {
      $0.everyScreenHasNotch = false
      $0.onboarding.doneHint.menuBarIcon = true
    }
    await store.send(.window(.screensChanged(everyScreenHasNotch: true))) {
      $0.everyScreenHasNotch = true
      $0.onboarding.doneHint.menuBarIcon = false
    }
    await store.finish()
    #expect(menuBarIcon.value == [true, false])
  }

  @Test
  func menuBarIconStaysOnWhileTheNotchCannotOpenVortex() async {
    let store = makeStore { $0.showMenuBarIcon = false }
    await store.send(.binding(.set(\.settings.openOnHover, false))) {
      $0.settings.openOnHover = false
      $0.onboarding.doneHint.notch = .click
    }
    await store.send(.binding(.set(\.settings.openOnClick, false))) {
      $0.settings.openOnClick = false
      $0.onboarding.doneHint = .init(notch: nil, menuBarIcon: true)
    }
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

  /// The shell works with any set of features, none at all included: it launches, shows them, and goes to the catalog
  /// and back.
  @Test(arguments: [[], [.home], [.home, .timer], [.home, .shelf], [.home, .tasks]] as [[FeatureDescriptor]])
  func theShellWorksWithAnySetOfFeatures(_ features: [FeatureDescriptor]) async {
    let store = makeStore(features: features) {
      $0.addedFeatures = features.map(\.id)
      $0.seenFeatures = features.map(\.id)
    }
    await launch(store)
    await store.finish()
    #expect(featureSwitches.value == features.map { "\($0.id):true" })
    #expect(store.state.sidebarFeatures == features)
    let tab = store.state.selectedTab
    await openByHover(store)
    await store.send(.tabSelected(.catalog)) {
      $0.selectedTab = .catalog
      $0.openReason = .click
    }
    await store.send(.window(.escapePressed)) {
      $0.openReason = nil
      $0.selectedTab = tab
    }
    #expect(windowLog.value == ["size:regular", "present:hover", "size:large"])
  }

  /// The launch no longer registers the login item by itself: Basics does, when the user leaves it. System Settings'
  /// own names are read before the onboarding can show its drawing of it.
  @Test
  func launchStartsFeaturesAndSetsUpTheShell() async {
    let firstLaunchSetUps = LockIsolated(0)
    let names = SystemSettingsNames(privacyAndSecurity: "Datenschutz & Sicherheit", accessibility: "Bedienungshilfen")
    let store = makeStore { $0.addedFeatures = ["timer", "shelf"] }
    store.dependencies.windowClient.events = { .finished }
    store.dependencies.hotkeyClient.presses = { _ in .finished }
    store.dependencies.systemClient.applyTheme = { _ in }
    store.dependencies.launchAtLoginClient.enableOnFirstLaunch = { firstLaunchSetUps.withValue { $0 += 1 } }
    store.dependencies.launchAtLoginClient.status = { .enabled }
    store.dependencies.permissionsClient.updates = { .finished }
    store.dependencies.permissionPage.requests = { .finished }
    store.dependencies.activeAppClient.activations = { .finished }
    store.dependencies.activeAppClient.terminations = { .finished }
    store.dependencies.systemSettingsNamesClient.names = { names }

    await store.send(.task)
    await store.receive(\.launchAtLoginStatusLoaded) { $0.launchAtLogin = .enabled }
    await store.receive(\.onboarding.systemSettingsNamesLoaded) { $0.onboarding.settingsNames = names }
    await store.receive(\.started) { $0.isStarted = true }
    await store.finish()
    #expect(menuBarIcon.value == [true])
    // A feature that isn't added isn't even stopped: none of its code runs.
    #expect(featureSwitches.value == ["timer:true", "shelf:true"])
    #expect(firstLaunchSetUps.value == 0)
  }

  // MARK: - Only features that run

  /// A feature the user hasn't added runs no code: the launch starts the added ones and stops none.
  @Test
  func launchStartsOnlyAddedFeatures() async {
    let store = makeStore(features: [.home, .timer, .shelf, .tasks]) { $0.addedFeatures = ["home", "timer", "tasks"] }
    await launch(store)
    await store.finish()
    #expect(featureSwitches.value == ["home:true", "timer:true", "tasks:true"])
  }

  /// On a fresh install the recommended features are added but wait for the user's choice: only Home runs meanwhile.
  @Test
  func nothingButHomeRunsBeforeTheUserChooses() async {
    let store = makeStore(features: [.home, .timer, .shelf]) {
      $0.addedFeatures = ["home", "timer", "shelf"]
      $0.featuresChosen = false
    }
    #expect(store.state.runningFeatures.map(\.id) == ["home"])
    #expect(store.state.sidebarFeatures.map(\.id) == ["home"])
    await launch(store)
    await store.finish()
    #expect(featureSwitches.value == ["home:true"])
  }

  /// A feature the maintainer paused for this release stays added, but it never runs and its permissions aren't asked
  /// for.
  @Test
  func aPausedFeatureNeverRunsButItsPermissionStaysOut() {
    let paused = FeatureDescriptor(
      id: "clipboard",
      title: "Clipboard",
      symbol: "list.clipboard",
      permissionNeeds: [PermissionNeed(.pasteboard, reason: "Keeps your clipboard history.")],
      suspension: "Doesn't work on this macOS yet."
    )
    let state = ShellFeature.State(features: [.home, .timer, paused], onboarding: .finished)
    #expect(state.addedFeatures.map(\.id) == ["home", "timer", "clipboard"])
    #expect(state.runningFeatures.map(\.id) == ["home", "timer"])
    #expect(state.permissionCatalog.entry(for: .pasteboard) == nil)
  }

  /// Indicators a feature left in the notch hide while it doesn't run, from the launch on and as it is removed.
  @Test
  func indicatorsOfFeaturesThatDontRunAreHidden() async {
    let store = makeStore(features: [.home, .timer, .shelf, .tasks]) { $0.addedFeatures = ["home", "timer", "tasks"] }
    await launch(store)
    await store.finish()
    #expect(hiddenIndicatorOwners.value == [["shelf"]])
    await store.send(.featureRemoved("timer")) {
      $0.settings.addedFeatures = ["home", "tasks"]
      $0.removedForUndo = "timer"
    }
    await clock.advance(by: .seconds(5))
    await store.receive(\.undoExpired) { $0.removedForUndo = nil }
    await store.finish()
    #expect(hiddenIndicatorOwners.value == [["shelf"], ["shelf", "timer"]])
  }

  /// The shortcut that opens a feature's tab is listened for only while the feature runs: removing it frees the keys.
  @Test
  func aRemovedFeaturesShortcutIsReleased() async {
    let listening = LockIsolated<Set<String>>([])
    let store = makeStore(features: [.home, .timer, .tasks])
    store.dependencies.hotkeyClient.presses = { hotkey in
      AsyncStream { continuation in
        listening.withValue { _ = $0.insert(hotkey.name) }
        continuation.onTermination = { _ in listening.withValue { _ = $0.remove(hotkey.name) } }
      }
    }
    let task = await launch(store)
    #expect(listening.value == ["openVortex", "open-home", "open-timer", "open-tasks"])
    await store.send(.featureRemoved("tasks")) {
      $0.settings.addedFeatures = ["home", "timer"]
      $0.removedForUndo = "tasks"
    }
    await clock.advance(by: .seconds(5))
    await store.receive(\.undoExpired) { $0.removedForUndo = nil }
    #expect(listening.value == ["openVortex", "open-home", "open-timer"])
    await task.cancel()
    await store.finish()
  }

  // MARK: - Safe mode and crashes

  /// Safe mode starts nothing but Home; a feature the user starts there runs on a trial.
  @Test
  func safeModeRunsOnlyHomeUntilAsked() async {
    let store = makeStore(features: [.home, .timer, .shelf], isSafeMode: true)
    await launch(store)
    await store.finish()
    #expect(featureSwitches.value == ["home:true"])
    await store.send(.startFeatureTapped("timer")) { $0.safeModeStarted = ["timer"] }
    await store.finish()
    #expect(featureSwitches.value == ["home:true", "timer:true"])
    #expect(trials.value == ["timer"])
    #expect(store.state.sidebarFeatures.map(\.id) == ["home", "timer"])
  }

  /// "Start All" ends safe mode: every added feature starts, each on a trial, so a crash right after still opens safe
  /// mode or stops the one that was started.
  @Test
  func startAllStartsEveryAddedFeature() async {
    let store = makeStore(features: [.home, .timer, .shelf, .tasks], isSafeMode: true) {
      $0.addedFeatures = ["home", "timer", "shelf"]
    }
    await launch(store)
    await store.send(.startFeatureTapped("shelf")) { $0.safeModeStarted = ["shelf"] }
    await store.send(.startAllTapped) {
      $0.isSafeMode = false
      $0.safeModeStarted = []
    }
    await store.finish()
    #expect(featureSwitches.value == ["home:true", "shelf:true", "timer:true"])
    #expect(trials.value == ["shelf", "timer"])
  }

  /// A feature stopped after a crash stays added; "Try Again" starts it on a trial, saved before it runs.
  @Test
  func aStoppedFeatureComesBackOnTryAgain() async {
    let store = makeStore { $0.stoppedFeatures = ["tasks"] }
    await launch(store)
    #expect(featureSwitches.value == ["timer:true", "shelf:true"])
    await store.send(.tryAgainTapped("tasks")) { $0.settings.stoppedFeatures = [] }
    #expect(saved.value.map(\.stoppedFeatures) == [[]])
    #expect(trials.value == ["tasks"])
    await clock.advance(by: .milliseconds(400))
    await store.finish()
    #expect(featureSwitches.value == ["timer:true", "shelf:true", "tasks:true"])
  }

  /// A new version may have fixed the crash: it forgets the stopped features. The same version keeps them, and a crash
  /// it blames stops one more.
  @Test
  func aNewVersionForgetsStoppedFeatures() {
    var settings = ShellSettings()
    settings.stoppedFeatures = ["tasks"]
    settings.stoppedInVersion = "0.1.4 (17)"
    var sameVersion = settings
    sameVersion.applyLaunch(.stop("clipboard"), version: "0.1.4 (17)")
    #expect(sameVersion.stoppedFeatures == ["tasks", "clipboard"])
    settings.applyLaunch(.normal, version: "0.1.5 (18)")
    #expect(settings.stoppedFeatures == [] && settings.stoppedInVersion == nil)
    settings.applyLaunch(.stop("clipboard"), version: "0.1.5 (18)")
    #expect(settings.stoppedFeatures == ["clipboard"] && settings.stoppedInVersion == "0.1.5 (18)")
  }

  /// Files go to the first running feature that takes them: none while Shelf isn't added, or before the user chooses.
  @Test
  func filesGoToTheFirstRunningFeatureThatTakesThem() {
    var notAdded = ShellSettings()
    notAdded.addedFeatures = ["home", "timer"]
    #expect(ShellFeature.State(settings: notAdded, features: [.home, .timer, .shelf]).fileFeature == nil)
    var notChosen = ShellSettings()
    notChosen.addedFeatures = ["home", "shelf"]
    notChosen.featuresChosen = false
    #expect(ShellFeature.State(settings: notChosen, features: [.home, .shelf]).fileFeature == nil)
    notChosen.featuresChosen = true
    #expect(ShellFeature.State(settings: notChosen, features: [.home, .shelf]).fileFeature?.id == "shelf")
  }

  /// Settings › General shows the short version; "Check for Updates" opens the latest release in the browser, through
  /// the file client as other pages open, and Vortex itself makes no request.
  @Test
  func checkForUpdatesOpensTheLatestReleaseInTheBrowser() async {
    let opened = LockIsolated<[URL]>([])
    let version = AppVersion(short: "0.1.2", build: "17")
    let store = TestStore(initialState: ShellFeature.State(features: [.timer], appVersion: version)) {
      ShellFeature()
    } withDependencies: {
      $0.fileClient.open = { url in opened.withValue { $0.append(url) } }
    }
    #expect(store.state.appVersion.short == "0.1.2")
    await store.send(.checkForUpdatesTapped)
    await store.finish()
    #expect(opened.value == [URL(string: "https://github.com/OrtexIsArtem/vortex/releases/latest")!])
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
