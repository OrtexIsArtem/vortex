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

  func makeStore(
    _ configure: (inout ShellSettings) -> Void = { _ in }
  ) -> TestStoreOf<ShellFeature> {
    var settings = ShellSettings()
    configure(&settings)
    let state = ShellFeature.State(settings: settings, features: [.timer, .shelf, .tasks])
    return TestStore(initialState: state) {
      ShellFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.windowClient.present = { [presented] reason in presented.withValue { $0.append(reason) } }
      $0.windowClient.dismiss = { [dismissals] in dismissals.withValue { $0 += 1 } }
      $0.windowClient.setMenuBarIconVisible = { [menuBarIcon] isVisible in menuBarIcon.withValue { $0.append(isVisible) } }
      $0.settingsClient.save = { [saved] settings in saved.withValue { $0.append(settings) } }
    }
  }

  /// Opens by hovering the notch for the default delay.
  func openByHover(_ store: TestStoreOf<ShellFeature>) async {
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .milliseconds(300))
    await store.receive(\.hoverDelayElapsed) {
      $0.isOpen = true
      $0.openReason = .hover
    }
  }

  // MARK: - Opening

  @Test
  func hoverOpensAfterTheDelay() async {
    let store = makeStore()
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await clock.advance(by: .milliseconds(299))
    #expect(presented.value.isEmpty)
    await clock.advance(by: .milliseconds(1))
    await store.receive(\.hoverDelayElapsed) {
      $0.isOpen = true
      $0.openReason = .hover
    }
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
    await store.send(.window(.notchClicked)) {
      $0.isOpen = true
      $0.openReason = .click
    }
    await store.send(.window(.notchClicked)) {
      $0.isOpen = false
      $0.openReason = nil
    }
    #expect(presented.value == [.click])
    #expect(dismissals.value == 1)
  }

  @Test
  func clickDoesNothingWhenTurnedOff() async {
    let store = makeStore { $0.openOnClick = false }
    await store.send(.window(.notchClicked))
    #expect(presented.value.isEmpty)
  }

  @Test
  func hotkeyAndMenuBarIconToggle() async {
    let store = makeStore()
    await store.send(.hotkey(.openVortex)) {
      $0.isOpen = true
      $0.openReason = .hotkey
    }
    await store.send(.window(.menuBarIconClicked)) {
      $0.isOpen = false
      $0.openReason = nil
    }
    await store.send(.window(.menuBarIconClicked)) {
      $0.isOpen = true
      $0.openReason = .menuBarIcon
    }
    #expect(presented.value == [.hotkey, .menuBarIcon])
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
    await store.receive(\.pointerLeaveDelayElapsed) {
      $0.isOpen = false
      $0.openReason = nil
    }
    #expect(dismissals.value == 1)
  }

  @Test
  func pointerLeavingDoesNotCloseAWindowOpenedByClick() async {
    let store = makeStore()
    await store.send(.window(.notchClicked)) {
      $0.isOpen = true
      $0.openReason = .click
    }
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
  func draggingOutKeepsTheWindowOpenUntilTheDrop() async {
    let store = makeStore()
    await openByHover(store)
    await store.send(.window(.pointerInsideWindowChanged(isInside: true))) { $0.isPointerInsideWindow = true }
    await store.send(.dragOutChanged(isDragging: true)) { $0.isDraggingOut = true }
    await store.send(.window(.pointerInsideWindowChanged(isInside: false))) { $0.isPointerInsideWindow = false }
    await store.send(.window(.clickedOutside))
    await clock.advance(by: .seconds(3))
    #expect(dismissals.value == 0)

    await store.send(.dragOutChanged(isDragging: false)) { $0.isDraggingOut = false }
    await clock.advance(by: .milliseconds(500))
    await store.receive(\.pointerLeaveDelayElapsed) {
      $0.isOpen = false
      $0.openReason = nil
    }
  }

  @Test
  func clickOutsideCloses() async {
    let store = makeStore()
    await store.send(.window(.notchClicked)) {
      $0.isOpen = true
      $0.openReason = .click
    }
    await store.send(.window(.clickedOutside)) {
      $0.isOpen = false
      $0.openReason = nil
    }
  }

  @Test
  func clickOutsideDoesNothingWhenTurnedOff() async {
    let store = makeStore { $0.closeOnClickOutside = false }
    await store.send(.window(.notchClicked)) {
      $0.isOpen = true
      $0.openReason = .click
    }
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
    await store.send(.hotkey(.openVortex)) {
      $0.isOpen = true
      $0.openReason = .hotkey
    }
    await store.send(.window(.escapePressed)) {
      $0.isOpen = false
      $0.openReason = nil
    }
    #expect(dismissals.value == 1)
  }

  // MARK: - Tabs

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
  func filesDraggedToTheNotchOpenTheShelfWithoutForgettingTheLastTab() async {
    let store = makeStore { $0.lastTab = "feature:tasks" }
    #expect(store.state.selectedTab == .feature("tasks"))
    await store.send(.window(.fileDragEnteredNotch)) {
      $0.isOpen = true
      $0.openReason = .fileDrag
      $0.selectedTab = .feature("shelf")
    }
    #expect(store.state.settings.lastTab == "feature:tasks")
  }

  @Test
  func settingsTabWithoutAnyFeatures() {
    let state = ShellFeature.State(features: [])
    #expect(state.selectedTab == .settings)
    #expect(state.sidebarFeatures.isEmpty)
  }

  // MARK: - Features

  @Test
  func turningAFeatureOffRemovesItFromTheSidebar() async {
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
    await store.send(.featuresMoved(fromOffsets: [2], toOffset: 0)) {
      $0.settings.featureOrder = ["tasks", "timer", "shelf"]
    }
    #expect(store.state.sidebarFeatures.map(\.id) == ["tasks", "timer", "shelf"])
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
  func menuBarIconStaysOnWithoutANotch() async {
    let store = makeStore { $0.showMenuBarIcon = false }
    await store.send(.window(.screensChanged(hasNotch: true)))
    await store.send(.window(.screensChanged(hasNotch: false))) { $0.hasNotchedScreen = false }
    await store.finish()
    #expect(menuBarIcon.value == [false, true])
  }

  @Test
  func screenChangesCloseTheWindow() async {
    let store = makeStore()
    await store.send(.window(.notchClicked)) {
      $0.isOpen = true
      $0.openReason = .click
    }
    await store.send(.window(.screensChanged(hasNotch: true))) {
      $0.isOpen = false
      $0.openReason = nil
    }
    #expect(dismissals.value == 1)
  }

  @Test
  func languageChangeAsksForARestart() async {
    let applied = LockIsolated<[AppLanguage]>([])
    let store = makeStore()
    store.dependencies.systemClient.applyLanguage = { language in applied.withValue { $0.append(language) } }
    await store.send(.binding(.set(\.settings.language, .english))) { $0.settings.language = .english }
    #expect(store.state.needsRestartForLanguage)
    await clock.advance(by: .milliseconds(400))
    await store.finish()
    #expect(applied.value == [.english])
    #expect(saved.value.last?.language == .english)
  }

  @Test
  func firstLaunchSetsUpLaunchAtLogin() async {
    let isEnabled = LockIsolated(false)
    let store = makeStore()
    store.dependencies.launchAtLoginClient.isEnabled = { isEnabled.value }
    store.dependencies.launchAtLoginClient.enableByDefault = { isEnabled.setValue(true) }
    store.dependencies.windowClient.events = { AsyncStream { $0.finish() } }
    store.dependencies.windowClient.hasNotchedScreen = { true }
    store.dependencies.hotkeyClient.presses = { AsyncStream { $0.finish() } }
    store.dependencies.systemClient.applyTheme = { _ in }

    await store.send(.task) {
      $0.settings.launchAtLoginConfigured = true
      $0.launchAtLogin = true
    }
    await store.receive(.window(.screensChanged(hasNotch: true)))
    await clock.advance(by: .milliseconds(400))
    #expect(saved.value.last?.launchAtLoginConfigured == true)
    #expect(menuBarIcon.value == [true])
  }
}
