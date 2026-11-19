import ComposableArchitecture
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureUtilityTemplate

@MainActor
struct UtilityTemplateTests {
  /// The action says hello in the closed notch for a moment, then the notch is as it was; a second press starts the
  /// moment again.
  @Test
  func theActionSaysHelloInTheNotchForAMoment() async {
    let clock = TestClock()
    let store = TestStore(initialState: UtilityTemplateFeature.State()) {
      UtilityTemplateFeature()
    } withDependencies: {
      $0.continuousClock = clock
    }
    await store.send(.sayHello) {
      $0.$indicators.withLock { $0[UtilityTemplateModule.id] = UtilityTemplateFeature.hello }
    }
    await clock.advance(by: .seconds(1))
    await store.send(.sayHello)
    await clock.advance(by: .seconds(1))
    #expect(store.state.indicators[UtilityTemplateModule.id] != nil)
    await clock.advance(by: .milliseconds(500))
    await store.receive(\.helloEnded) {
      $0.$indicators.withLock { $0[UtilityTemplateModule.id] = nil }
    }
  }

  /// The template is a utility: no tab, one utility action that follows the rules, run with the window closed, as it
  /// shows itself in the closed notch, and the shortcut of its own that runs it.
  @Test
  func itIsAUtilityWithOneActionThatFollowsTheRules() {
    #expect(UtilityTemplateModule.kind == .utility && !UtilityTemplateModule.descriptor.hasTab)
    let actions = UtilityTemplateModule.makeUtilityActions()
    #expect(actions.count == 1)
    #expect(UtilityAction.problems(actions, feature: UtilityTemplateModule.id).isEmpty)
    #expect(actions[0].window == .closed)
    #expect(actions[0].shortcut == Hotkey.sayHello.name)
    #expect(UtilityTemplateModule.makeHomeWidgets().isEmpty)
  }
}
