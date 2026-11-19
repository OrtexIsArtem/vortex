import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import VortexShell

/// Home's utilities dock, which the shell owns and Home draws: its buttons in catalog order with their marks, the strip
/// that grows the window right, what closes it, and what a button runs.
@MainActor
struct UtilitiesDockTests {
  let shell = ShellFeatureTests()
  /// What happened to the window and the actions, in order.
  let log = LockIsolated<[String]>([])

  static let copy = UtilityActionInfo(
    id: "screentext.copy", feature: "screentext", window: .closed, permission: .screenRecording, shortcut: "copyScreenText"
  )
  static let lock = UtilityActionInfo(
    id: "keyboard.lock", feature: "keyboard", window: .open, permission: .accessibility, shortcut: "lockKeyboard"
  )
  static let toggle = UtilityActionInfo(id: "timer.toggle", feature: "timer", window: .unchanged)

  /// Home, Timer, Screen Text and keyboard cleaning added; the window opens on Home.
  func makeStore(_ actions: [UtilityActionInfo] = [copy, lock]) -> TestStoreOf<ShellFeature> {
    let store = shell.makeStore(features: [.home, .timer, .screenText, .cleaning]) {
      $0.addedFeatures = ["home", "timer", "screentext", "keyboard"]
      $0.lastTab = "feature:home"
    }
    store.dependencies.featuresClient.performUtilityAction = { [log] _, id in log.withValue { $0.append("perform \(id)") } }
    store.dependencies.windowClient.dismiss = { [log] in log.withValue { $0.append("dismiss") } }
    store.dependencies.windowClient.present = { [log] reason in log.withValue { $0.append("present \(reason)") } }
    store.dependencies.windowClient.setSize = { [log] size in log.withValue { $0.append("size \(size)") } }
    store.dependencies.hotkeyClient.shortcut = { hotkey in hotkey.name == "copyScreenText" ? "⌃⌥T" : nil }
    store.exhaustivity = .off(showSkippedAssertions: false)
    return store
  }

  /// Opens the window on Home with these actions running, and opens the dock with its button.
  func openDock(_ store: TestStoreOf<ShellFeature>, _ actions: [UtilityActionInfo] = [copy, lock]) async {
    await store.send(.utilityActionsLoaded(actions))
    await store.send(.window(.notchClicked(feature: nil)))
    await store.send(.dockToggled)
    await store.receive(\.dockKeysLoaded)
    #expect(store.state.isDockOpen)
  }

  // MARK: - Its buttons

  /// The dock lists the running utility actions in catalog order: a feature's own, then the utilities', each in the
  /// user's order, as the catalog lists them; only running ones.
  @Test
  func theButtonsAreTheRunningActionsInCatalogOrder() {
    var settings = ShellSettings()
    settings.addedFeatures = ["home", "timer", "screentext", "keyboard"]
    settings.featureOrder = ["keyboard", "screentext", "timer"]
    var state = ShellFeature.State(
      settings: settings, features: [.home, .timer, .screenText, .cleaning], onboarding: .finished
    )
    // In sidebar order, as the shell reads them.
    state.utilityActions = [Self.lock, Self.copy, Self.toggle]
    #expect(state.dockActions.map(\.id) == ["timer.toggle", "keyboard.lock", "screentext.copy"])
  }

  /// A button carries the yellow warning while the permission its action needs reads `notGranted`; none before the
  /// first read, and none once macOS granted it, even for after a restart.
  @Test
  func aButtonIsMarkedWhileItsPermissionIsOff() {
    let state = ShellFeature.State(features: [.home, .screenText], onboarding: .finished)
    #expect(state.dockWarning(Self.copy) == nil)
    state.$permissionStatuses.withLock { $0 = [.screenRecording: .notGranted] }
    #expect(state.dockWarning(Self.copy) == .screenRecording)
    #expect(state.dockWarning(Self.toggle) == nil)
    state.$permissionStatuses.withLock { $0 = [.screenRecording: .grantedAfterRestart] }
    #expect(state.dockWarning(Self.copy) == nil)
  }

  /// The button opens the strip only in the open window, on a tab, with something to offer and no tab holding the
  /// focus: then the window grows right by the strip, deliberately, so the pointer leaving no longer closes it, and the
  /// tooltips' keys are read. The button again puts it away, and the window back.
  @Test
  func theButtonGrowsTheWindowByTheStripAndPutsItAway() async {
    let store = makeStore()
    // Closed, nothing opens.
    await store.send(.dockToggled)
    #expect(!store.state.isDockOpen)
    await store.send(.utilityActionsLoaded([]))
    await store.send(.window(.notchHoverChanged(isInside: true)))
    await shell.clock.advance(by: .milliseconds(300))
    await store.receive(\.hoverDelayElapsed)
    // Nothing to offer: the button is the pencil, which the shell never sees.
    await store.send(.dockToggled)
    #expect(!store.state.isDockOpen)
    await store.send(.utilityActionsLoaded([Self.copy, Self.lock]))
    await store.send(.dockToggled)
    await store.receive(\.dockKeysLoaded)
    #expect(store.state.isDockOpen && store.state.openReason == .click)
    #expect(store.state.dockKeys == ["screentext.copy": "⌃⌥T"])
    #expect(store.state.windowSize == .dock)
    await store.send(.window(.pointerInsideWindowChanged(isInside: false)))
    await shell.clock.advance(by: .seconds(3))
    #expect(store.state.isOpen)
    await store.send(.dockToggled)
    #expect(!store.state.isDockOpen && store.state.windowSize == .regular)
    await store.finish()
    #expect(log.value == ["size regular", "present hover", "size dock", "size regular"])
  }

  /// While a tab has the focus, as Home's editor does, the strip doesn't open.
  @Test
  func theStripWaitsWhileATabHasTheFocus() async {
    let store = makeStore()
    await store.send(.utilityActionsLoaded([Self.copy]))
    await store.send(.window(.notchClicked(feature: nil)))
    await store.send(.windowRequested("home", WindowRequest(size: .large, isFocused: true)))
    await store.send(.dockToggled)
    #expect(!store.state.isDockOpen)
  }

  // MARK: - What closes it

  /// Esc puts the strip away and leaves the window open; the next Esc closes the window.
  @Test
  func escapePutsTheStripAwayFirst() async {
    let store = makeStore()
    await openDock(store)
    await store.send(.window(.escapePressed))
    #expect(!store.state.isDockOpen && store.state.isOpen)
    await store.send(.window(.escapePressed))
    #expect(!store.state.isOpen)
  }

  /// A click in another app puts the strip away, and closes the window by the usual rule; a click in the sidebar is a
  /// click outside the strip too.
  @Test
  func aClickOutsidePutsTheStripAway() async {
    let store = makeStore()
    await store.send(.binding(.set(\.settings.closeOnClickOutside, false)))
    await openDock(store)
    await store.send(.window(.clickedOutside))
    #expect(!store.state.isDockOpen && store.state.isOpen)

    await store.send(.dockToggled)
    await store.receive(\.dockKeysLoaded)
    await store.send(.tabSelected(.feature("home")))
    #expect(!store.state.isDockOpen && store.state.selectedTab == .feature("home"))

    await store.send(.binding(.set(\.settings.closeOnClickOutside, true)))
    await store.send(.dockToggled)
    await store.receive(\.dockKeysLoaded)
    await store.send(.window(.clickedOutside))
    #expect(!store.state.isDockOpen && !store.state.isOpen)
  }

  /// Home's own click outside the strip, leaving Home's tab, and the window closing each put the strip away.
  @Test
  func leavingHomeOrClosingTheWindowPutsTheStripAway() async {
    let store = makeStore()
    await openDock(store)
    await store.send(.dockClosed)
    #expect(!store.state.isDockOpen)

    await store.send(.dockToggled)
    await store.receive(\.dockKeysLoaded)
    await store.send(.featureHotkeyPressed("timer"))
    #expect(!store.state.isDockOpen && store.state.selectedTab == .feature("timer"))

    await store.send(.tabSelected(.feature("home")))
    await store.send(.dockToggled)
    await store.receive(\.dockKeysLoaded)
    await store.send(.window(.notchClicked(feature: nil)))
    #expect(!store.state.isDockOpen && !store.state.isOpen)
    // The next open starts without it, at the regular size.
    await store.send(.window(.notchClicked(feature: nil)))
    #expect(!store.state.isDockOpen && store.state.windowSize == .regular)
  }

  /// The dock's pencil opens Home's editor, whose request for the large window takes the strip's place: one resize, from
  /// the strip to the editor's size.
  @Test
  func theEditorsRequestTakesTheStripsPlace() async {
    let store = makeStore()
    await openDock(store)
    log.setValue([])
    await store.send(.windowRequested("home", WindowRequest(size: .large, isFocused: true)))
    #expect(!store.state.isDockOpen && store.state.windowSize == .large)
    await store.finish()
    #expect(log.value == ["size large"])
  }

  /// With no action left running, as when the utilities stop, the strip goes.
  @Test
  func theStripGoesWithItsLastAction() async {
    let store = makeStore()
    await openDock(store)
    await store.send(.utilityActionsLoaded([]))
    #expect(!store.state.isDockOpen)
  }

  // MARK: - What a button runs

  /// A button puts the strip away, then runs its action as its shortcut does: one that works on the screen with the
  /// window closed first.
  @Test
  func aButtonThatNeedsTheWindowClosedClosesItThenRuns() async {
    let store = makeStore()
    await openDock(store)
    log.setValue([])
    await store.send(.utilityActionPressed("screentext.copy"))
    #expect(!store.state.isDockOpen && !store.state.isOpen)
    await store.finish()
    #expect(log.value == ["dismiss", "perform screentext.copy"])
  }

  /// One whose own screen covers the window runs with the window open, at the regular size.
  @Test
  func aButtonThatNeedsTheWindowOpenRunsInIt() async {
    let store = makeStore()
    await openDock(store)
    log.setValue([])
    await store.send(.utilityActionPressed("keyboard.lock"))
    #expect(!store.state.isDockOpen && store.state.isOpen && store.state.windowSize == .regular)
    await store.finish()
    #expect(log.value.sorted() == ["perform keyboard.lock", "size regular"])
  }

  /// One that doesn't care runs with the window as it is, the strip put away.
  @Test
  func aButtonThatDoesntCareRunsWithTheWindowAsItIs() async {
    let store = makeStore()
    await openDock(store, [Self.toggle])
    log.setValue([])
    await store.send(.utilityActionPressed("timer.toggle"))
    #expect(!store.state.isDockOpen && store.state.isOpen)
    await store.finish()
    #expect(log.value.sorted() == ["perform timer.toggle", "size regular"])
  }
}
