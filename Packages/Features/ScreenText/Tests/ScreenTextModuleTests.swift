import ComposableArchitecture
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureScreenText

@MainActor
struct ScreenTextModuleTests {
  /// A feature of its own without a tab, which keeps nothing and waits for the user's choice to be added.
  @Test
  func itHasNoTabKeepsNothingAndIsNotRecommended() {
    let d = ScreenTextModule.descriptor
    #expect(d.id == "screentext" && d.symbol == "text.viewfinder")
    #expect(!d.hasTab)
    #expect(d.keeps == nil && d.dataFolder == nil && d.eraseNote == nil)
    #expect(!d.isRecommended && !d.isBuiltIn && !d.hasOnboardingStep)
    #expect(!d.author.isEmpty)
    #expect(ScreenTextModule.makeHomeWidgets().isEmpty)
    #expect(ScreenTextModule.makeSettings() != nil)
  }

  /// It reads the screen, so it needs Screen Recording, with its own reason, and nothing else.
  @Test
  func itNeedsScreenRecordingAlone() {
    #expect(ScreenTextModule.permissionNeeds.map(\.permission) == [.screenRecording])
    #expect(ScreenTextModule.descriptor.permissionNeeds == ScreenTextModule.permissionNeeds)
  }

  /// Its one utility action works on the screen, so the shell closes the window first; its shortcut is the module's
  /// own, none by default, and runs the same action.
  @Test
  func itsActionNeedsTheWindowClosedAndHasTheShortcut() {
    let actions = ScreenTextModule.makeUtilityActions()
    #expect(actions.map(\.id) == ["screentext.copy"])
    #expect(UtilityAction.problems(actions, feature: ScreenTextModule.id).isEmpty)
    let copy = actions[0]
    #expect(copy.window == .closed)
    #expect(copy.permission == .screenRecording)
    #expect(copy.shortcut == Hotkey.copyScreenText.name)
    #expect(copy.symbol == ScreenTextModule.symbol)
  }
}
