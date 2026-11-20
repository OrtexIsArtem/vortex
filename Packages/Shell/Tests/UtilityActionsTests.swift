import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import VortexShell

/// The running features' utility actions: the shell reads them, listens for their shortcuts while they run, and runs
/// each one after making the window what it needs. A feature never opens or closes the window itself.
@MainActor
struct UtilityActionsTests {
  let shell = ShellFeatureTests()
  /// What happened to the window and the actions, in order.
  let log = LockIsolated<[String]>([])
  /// The shortcuts listened for, each time one was asked for, and the streams, which a test ends at its end.
  let asked = LockIsolated<[String]>([])
  let listening = LockIsolated<Set<String>>([])
  let streams = LockIsolated<[String: AsyncStream<Void>.Continuation]>([:])

  static let copy = UtilityActionInfo(id: "screentext.copy", feature: "screentext", window: .closed, shortcut: "copyScreenText")
  static let clean = UtilityActionInfo(id: "keyboard.lock", feature: "keyboard", window: .open)
  static let toggle = UtilityActionInfo(id: "timer.toggle", feature: "timer", window: .unchanged, shortcut: "toggleTimer")

  func makeStore(_ actions: [UtilityActionInfo] = [copy, clean, toggle]) -> TestStoreOf<ShellFeature> {
    let store = shell.makeStore(features: [.home, .timer, .screenText, .cleaning]) {
      $0.addedFeatures = ["home", "timer", "screentext", "keyboard"]
      $0.lastTab = "feature:timer"
    }
    store.dependencies.featuresClient.utilityActions = { ids in
      ids.flatMap { id in actions.filter { $0.feature == id } }
    }
    store.dependencies.featuresClient.performUtilityAction = { [log] _, id in log.withValue { $0.append("perform \(id)") } }
    store.dependencies.windowClient.dismiss = { [log] in log.withValue { $0.append("dismiss") } }
    store.dependencies.windowClient.present = { [log] reason in log.withValue { $0.append("present \(reason)") } }
    store.dependencies.hotkeyClient.presses = { [asked, listening, streams] hotkey in
      asked.withValue { $0.append(hotkey.name) }
      let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
      listening.withValue { _ = $0.insert(hotkey.name) }
      streams.withValue { $0[hotkey.name] = continuation }
      continuation.onTermination = { _ in listening.withValue { _ = $0.remove(hotkey.name) } }
      return stream
    }
    return store
  }

  /// Ends every shortcut's stream, so the effects that listen end too.
  func endShortcuts() {
    streams.value.values.forEach { $0.finish() }
  }

  /// At launch the shell reads the running features' actions, in sidebar order, and listens for each one's shortcut
  /// while its feature runs: removing the feature frees the keys, Undo listens again.
  @Test
  func theRunningFeaturesActionsAreReadAndTheirShortcutsListenedFor() async {
    let store = makeStore()
    let task = await shell.launch(store)
    await store.receive(\.utilityActionsLoaded) { $0.utilityActions = [Self.toggle, Self.copy, Self.clean] }

    await store.send(.featureRemoved("screentext")) {
      $0.settings.addedFeatures = ["home", "timer", "keyboard"]
      $0.removedForUndo = "screentext"
    }
    await store.receive(\.utilityActionsLoaded) { $0.utilityActions = [Self.toggle, Self.clean] }
    #expect(!listening.value.contains("copyScreenText"))
    await store.send(.undoRemoveTapped) {
      $0.settings.addedFeatures = ["home", "timer", "screentext", "keyboard"]
      $0.removedForUndo = nil
    }
    await store.receive(\.utilityActionsLoaded) { $0.utilityActions = [Self.toggle, Self.copy, Self.clean] }
    await shell.clock.advance(by: .milliseconds(400))
    await task.cancel()
    endShortcuts()
    await store.finish()
    #expect(asked.value.filter { $0 == "copyScreenText" }.count == 2)
    #expect(asked.value.filter { $0 == "toggleTimer" }.count == 1)
  }

  /// A shortcut press runs its action as a click would.
  @Test
  func aShortcutRunsItsAction() async {
    let store = makeStore()
    let task = await shell.launch(store)
    await store.receive(\.utilityActionsLoaded) { $0.utilityActions = [Self.toggle, Self.copy, Self.clean] }
    for _ in 0..<100 where streams.value["copyScreenText"] == nil {
      await Task.yield()
    }
    streams.value["copyScreenText"]?.yield()
    await store.receive(\.utilityActionPressed)
    await task.cancel()
    endShortcuts()
    await store.finish()
    #expect(log.value == ["perform screentext.copy"])
  }

  /// An action that works on the screen runs with the window closed: an open window closes first, then the action
  /// runs, so a frozen screen or a notch message never sits over or behind it; a closed window stays closed.
  @Test
  func anActionThatNeedsTheWindowClosedClosesItFirst() async {
    let store = makeStore()
    await store.send(.binding(.set(\.utilityActions, [Self.copy]))) { $0.utilityActions = [Self.copy] }
    await store.send(.utilityActionPressed("screentext.copy"))
    await store.finish()
    #expect(log.value == ["perform screentext.copy"])

    log.setValue([])
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = .click }
    await store.send(.utilityActionPressed("screentext.copy")) { $0.openReason = nil }
    await store.finish()
    #expect(log.value == ["present click", "dismiss", "perform screentext.copy"])
  }

  /// An action whose own screen covers the window, as keyboard cleaning's, runs with the window open: a closed window
  /// opens first. One that doesn't care runs with the window as it is.
  @Test
  func anActionThatNeedsTheWindowOpenOpensItFirstAndOneThatDoesntCareLeavesIt() async {
    let store = makeStore()
    await store.send(.binding(.set(\.utilityActions, [Self.clean, Self.toggle]))) { $0.utilityActions = [Self.clean, Self.toggle] }
    await store.send(.utilityActionPressed("keyboard.lock")) { $0.openReason = .hotkey }
    await store.finish()
    #expect(log.value == ["present hotkey", "perform keyboard.lock"])

    log.setValue([])
    await store.send(.utilityActionPressed("keyboard.lock"))
    await store.send(.utilityActionPressed("timer.toggle"))
    await store.finish()
    #expect(log.value == ["perform keyboard.lock", "perform timer.toggle"])
  }

  /// An action whose permission reads `notGranted` can't work: its click or its shortcut opens that permission's page at
  /// once instead, and the action doesn't run. The window doesn't open for it first, so nothing flashes on the screen;
  /// an open one closes for the page, as for any page. So for every utility, whatever its action needs of the window.
  /// Before the first read, and once macOS granted it, even for after a restart, the action runs and its feature
  /// decides. Under a utility's cover it neither runs nor opens a page.
  @Test
  func anActionWithoutItsPermissionOpensItsPageInstead() async {
    let lock = UtilityActionInfo(id: "keyboard.lock", feature: "keyboard", window: .open, permission: .accessibility)
    let copy = UtilityActionInfo(id: "screentext.copy", feature: "screentext", window: .closed, permission: .screenRecording)
    let store = makeStore()
    store.exhaustivity = .off(showSkippedAssertions: false)
    store.dependencies.onboardingWindow.present = { _, _ in }
    store.dependencies.onboardingWindow.hide = { _ in }
    store.dependencies.onboardingProgress.save = { _ in }
    store.dependencies.permissionsClient.setFrequentChecks = { _ in }
    await store.send(.binding(.set(\.utilityActions, [lock, copy])))
    store.state.$permissionStatuses.withLock { $0 = [.accessibility: .notGranted, .screenRecording: .notGranted] }

    // The window closed, as keyboard cleaning's shortcut finds it: it stays closed, and Accessibility's page opens.
    await store.send(.utilityActionPressed("keyboard.lock"))
    await store.receive(\.onboarding.pageRequested)
    #expect(!store.state.isOpen)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .accessibility, kind: .request), .window))
    #expect(log.value.isEmpty)

    // The window open, as the dock's button finds it: it closes, and Screen Recording's page opens.
    await store.send(.window(.notchClicked(feature: nil)))
    log.setValue([])
    await store.send(.utilityActionPressed("screentext.copy"))
    await store.receive(\.onboarding.pageRequested)
    #expect(!store.state.isOpen)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .screenRecording, kind: .request), .window))
    #expect(log.value == ["dismiss"])

    // Granted for after a restart, or not read yet: the action runs as usual, and its feature decides.
    store.state.$permissionStatuses.withLock { $0 = [.accessibility: .grantedAfterRestart] }
    log.setValue([])
    await store.send(.utilityActionPressed("keyboard.lock"))
    await store.send(.utilityActionPressed("screentext.copy"))
    await store.finish()
    #expect(log.value == ["present hotkey", "perform keyboard.lock", "dismiss", "perform screentext.copy"])

    // Under a utility's cover, as keyboard cleaning's lock screen: nothing runs and no page opens.
    await store.send(.window(.notchClicked(feature: nil)))
    @Shared(.windowCover) var cover
    $cover.withLock { $0 = WindowCover(feature: "keyboard", holdsKeyboard: true) }
    store.state.$permissionStatuses.withLock { $0 = [.accessibility: .notGranted, .screenRecording: .notGranted] }
    await store.send(.onboarding(.closeTapped))
    log.setValue([])
    await store.send(.utilityActionPressed("keyboard.lock"))
    await store.send(.utilityActionPressed("screentext.copy"))
    await store.finish()
    #expect(log.value.isEmpty)
    #expect(store.state.onboarding.presentation == .hidden)
    #expect(store.state.isOpen)
    $cover.withLock { $0 = nil }
  }

  /// While the window must stay open (the erase question, a utility's cover as keyboard cleaning's lock screen), an
  /// action that needs it closed doesn't run; neither does one of a feature that doesn't run.
  @Test
  func nothingRunsWhileTheWindowMustStayOrForAFeatureThatDoesntRun() async {
    let store = makeStore()
    await store.send(.binding(.set(\.utilityActions, [Self.copy]))) { $0.utilityActions = [Self.copy] }
    await store.send(.window(.notchClicked(feature: nil))) { $0.openReason = .click }
    await store.send(.binding(.set(\.eraseConfirmation, "tasks"))) { $0.eraseConfirmation = "tasks" }
    await store.send(.utilityActionPressed("screentext.copy"))
    await store.send(.binding(.set(\.eraseConfirmation, nil))) { $0.eraseConfirmation = nil }
    // The cover is the utility's to put up: here as keyboard cleaning puts its lock screen up.
    store.exhaustivity = .off(showSkippedAssertions: false)
    @Shared(.windowCover) var cover
    $cover.withLock { $0 = WindowCover(feature: "keyboard", holdsKeyboard: true) }
    await store.send(.utilityActionPressed("screentext.copy"))
    await store.send(.utilityActionPressed("tasks.capture"))
    await store.finish()
    #expect(log.value == ["present click"])
    #expect(store.state.isOpen)
    $cover.withLock { $0 = nil }
  }
}
