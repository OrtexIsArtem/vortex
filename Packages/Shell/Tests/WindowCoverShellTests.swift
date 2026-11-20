import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import VortexShell

/// A utility's cover over the window, as keyboard cleaning's lock screen: while it shows, the window stays open and
/// Vortex holds the keyboard if the cover asks; when it goes, the window closes with it.
@MainActor
struct WindowCoverShellTests {
  let shell = ShellFeatureTests()
  /// The keyboard held (true) and let go (false), in order.
  let holds = LockIsolated<[Bool]>([])
  let passed = LockIsolated<[KeyboardKey]>([])

  static let lockScreen = WindowCover(feature: "keyboard", holdsKeyboard: true)

  func makeStore() -> TestStoreOf<ShellFeature> {
    let store = shell.makeStore(features: [.home, .timer, .cleaning]) {
      $0.addedFeatures = ["home", "timer", "keyboard"]
    }
    store.dependencies.windowClient.holdKeyboard = { [holds] isHeld in holds.withValue { $0.append(isHeld) } }
    store.dependencies.keyboardLockClient.reportPassed = { [passed] key in passed.withValue { $0.append(key) } }
    // The pages that open once the cover is down.
    store.dependencies.onboardingWindow.present = { _, _ in }
    store.dependencies.onboardingWindow.hide = { _ in }
    store.dependencies.onboardingProgress.save = { _ in }
    store.dependencies.permissionsClient.setFrequentChecks = { _ in }
    store.exhaustivity = .off(showSkippedAssertions: false)
    return store
  }

  /// Puts the cover up or takes it down, as the utility does, and lets the shell hear of it.
  func cover(_ cover: WindowCover?, _ store: TestStoreOf<ShellFeature>) async {
    @Shared(.windowCover) var shared
    $shared.withLock { $0 = cover }
    await store.send(.windowCoverChanged(cover))
  }

  /// Nothing the window usually closes on closes it under the cover: the pointer leaving, a click outside, Esc, the menu
  /// bar icon, the shortcut; new displays move it there. Vortex holds the keyboard meanwhile. When the cover goes, the
  /// keys go back and the window closes.
  @Test
  func aCoverKeepsTheWindowOpenUntilItGoesThenClosesIt() async {
    let store = makeStore()
    await shell.openByHover(store)
    await cover(Self.lockScreen, store)
    await store.send(.window(.pointerInsideWindowChanged(isInside: true)))
    await store.send(.window(.pointerInsideWindowChanged(isInside: false)))
    await shell.clock.advance(by: .seconds(3))
    await store.send(.window(.clickedOutside))
    await store.send(.window(.escapePressed))
    await store.send(.window(.menuBarIconClicked))
    await store.send(.openHotkeyPressed)
    await store.send(.window(.screensChanged(everyScreenHasNotch: true)))
    await store.finish()
    #expect(store.state.isOpen)
    #expect(shell.dismissals.value == 0)
    #expect(shell.presented.value == [.hover, .hover])
    #expect(holds.value == [true])

    await cover(nil, store)
    await store.finish()
    #expect(!store.state.isOpen)
    #expect(holds.value == [true, false])
    #expect(shell.dismissals.value == 1)
  }

  /// A cover never outlives its utility: one that stops, here removed, with its cover still up loses it, and the window,
  /// which nothing else could close, closes with it; the keys go back. The utility here never takes its cover down: its
  /// stop (`setEnabled(false)`) does nothing. Another utility stopping leaves the cover as it is.
  @Test
  func aCoverGoesWithItsUtility() async {
    let store = shell.makeStore(features: [.home, .timer, .screenText, .cleaning]) {
      $0.addedFeatures = ["home", "timer", "screentext", "keyboard"]
    }
    store.dependencies.windowClient.holdKeyboard = { [holds] isHeld in holds.withValue { $0.append(isHeld) } }
    store.exhaustivity = .off(showSkippedAssertions: false)
    await shell.openByHover(store)
    await cover(Self.lockScreen, store)
    await store.send(.featureRemoved("screentext"))
    #expect(store.state.windowCover == Self.lockScreen && store.state.isOpen)
    await store.send(.featureRemoved("keyboard"))
    #expect(store.state.windowCover == nil)
    #expect(!store.state.isOpen)
    await store.finish()
    #expect(holds.value == [true, false])
    // With nothing over it, Esc, the notch and the shortcut answer again.
    await store.send(.openHotkeyPressed)
    #expect(store.state.isOpen)
    await store.send(.window(.escapePressed))
    #expect(!store.state.isOpen)
  }

  /// A key that got past the lock and went down in the held window goes to the lock's presses, as the lock's own.
  @Test
  func aKeyThatReachesTheHeldWindowGoesToTheLock() async {
    let store = makeStore()
    await shell.openByHover(store)
    await cover(Self.lockScreen, store)
    await store.send(.window(.keyPressedWhileHeld(.q)))
    await store.finish()
    #expect(passed.value == [.q])
  }

  /// A cover that comes while the window is closed opens it: a cover never shows over nothing.
  @Test
  func aCoverThatComesWhileTheWindowIsClosedOpensIt() async {
    let store = makeStore()
    await cover(Self.lockScreen, store)
    #expect(store.state.isOpen)
    await cover(nil, store)
    #expect(!store.state.isOpen)
  }

  /// Under the cover an action that needs the window closed doesn't run, and the tabs and the catalog can't be reached.
  @Test
  func underTheCoverNothingTakesTheWindow() async {
    let store = makeStore()
    let runs = LockIsolated<[String]>([])
    store.dependencies.featuresClient.performUtilityAction = { _, id in runs.withValue { $0.append(id) } }
    await store.send(.utilityActionsLoaded([UtilityActionInfo(id: "screentext.copy", feature: "timer", window: .closed)]))
    await shell.openByHover(store)
    await cover(Self.lockScreen, store)
    await store.send(.utilityActionPressed("screentext.copy"))
    await store.finish()
    #expect(runs.value.isEmpty)
    #expect(store.state.isOpen)
  }

  /// A required permission that goes under the cover blocks Vortex only once the cover is down, as keyboard cleaning's
  /// Accessibility, whose loss ends its lock: the window closes and the blocking page opens then.
  @Test
  func aRequiredLossUnderTheCoverWaitsForItToGo() async {
    let store = makeStore()
    await store.send(.binding(.set(\.requiredPermissions, [.accessibility])))
    store.state.$permissionStatuses.withLock { $0 = [.accessibility: .granted] }
    await shell.openByHover(store)
    await cover(Self.lockScreen, store)
    await store.send(.permissionStatusesChanged([.accessibility: .notGranted]))
    #expect(store.state.isBlocked && store.state.isOpen)
    #expect(store.state.onboarding.presentation == .hidden)
    await cover(nil, store)
    await store.receive(\.onboarding.blocked)
    #expect(!store.state.isOpen)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .accessibility, kind: .blocked), .window))
  }

  /// A page a feature asks for once its cover is down, as keyboard cleaning's after a lock macOS refused, opens with
  /// the notch window closed; the refused one says to turn the switch off and on again.
  @Test
  func aRefusedPageOpensOnceTheCoverIsDown() async {
    let store = makeStore()
    await shell.openByHover(store)
    await cover(Self.lockScreen, store)
    await cover(nil, store)
    await store.send(.refusedPageRequested(.accessibility))
    await store.receive(\.onboarding.pageRequested)
    #expect(!store.state.isOpen)
    #expect(store.state.onboarding.presentation == .single(.init(permission: .accessibility, kind: .lockRefused), .window))
  }
}
