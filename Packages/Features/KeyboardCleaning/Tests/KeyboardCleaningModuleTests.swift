import ComposableArchitecture
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureKeyboardCleaning

@MainActor
struct KeyboardCleaningModuleTests {
  /// A utility, recommended, which keeps nothing: added on a fresh install, and kept added for whoever had it in Home.
  @Test
  func itIsARecommendedUtilityThatKeepsNothing() {
    let d = KeyboardCleaningModule.descriptor
    #expect(d.id == "keyboard" && d.symbol == "keyboard")
    #expect(d.kind == .utility && !d.hasTab)
    #expect(d.isRecommended && !d.isBuiltIn && !d.isBeta && !d.hasOnboardingStep)
    #expect(d.keeps == nil && d.dataFolder == nil && d.eraseNote == nil)
    #expect(!d.author.isEmpty)
    #expect(KeyboardCleaningModule.makeHomeWidgets().isEmpty)
  }

  /// It locks the keyboard, so it needs Accessibility, with its own reason, and nothing else: only once it is added does
  /// the onboarding ask for it.
  @Test
  func itNeedsAccessibilityAlone() {
    #expect(KeyboardCleaningModule.permissionNeeds.map(\.permission) == [.accessibility])
    #expect(KeyboardCleaningModule.descriptor.permissionNeeds == KeyboardCleaningModule.permissionNeeds)
  }

  /// Its one action covers the window with the lock screen, so the shell opens the window first; its warning names
  /// Accessibility, and its shortcut is its own, none by default.
  @Test
  func itsActionNeedsTheWindowOpenAndHasTheShortcut() {
    let actions = KeyboardCleaningModule.makeUtilityActions()
    #expect(actions.map(\.id) == ["keyboard.lock"])
    #expect(UtilityAction.problems(actions, feature: KeyboardCleaningModule.id).isEmpty)
    let lock = actions[0]
    #expect(lock.window == .open)
    #expect(lock.permission == .accessibility)
    #expect(lock.shortcut == Hotkey.lockKeyboard.name)
    #expect(lock.symbol == KeyboardCleaningModule.symbol)
  }

  /// The lock screen is its cover over the window, and its settings hold the Accessibility row.
  @Test
  func itHasACoverAndSettings() {
    #expect(KeyboardCleaningModule.makeWindowCover() != nil)
    #expect(KeyboardCleaningModule.makeSettings() != nil)
  }
}
