import SwiftUI
import Testing

@testable import VortexCore

/// The one-click actions features offer as utilities, which the shell places, and the rules they follow.
@MainActor
struct UtilityActionTests {
  func action(_ id: String, window: UtilityAction.WindowNeed = .closed) -> UtilityAction {
    UtilityAction(id: id, feature: "screentext", symbol: "text.viewfinder", label: "Copy Text", help: "Copy text", window: window) {}
  }

  @Test
  func aFeatureOffersAtMostTwoActionsWithIdsOfItsOwn() {
    #expect(UtilityAction.problems([], feature: "screentext").isEmpty)
    #expect(UtilityAction.problems([action("screentext.copy")], feature: "screentext").isEmpty)
    #expect(UtilityAction.problems([action("screentext.copy"), action("screentext.qr")], feature: "screentext").isEmpty)
    // Three actions, another feature's id, an id with no name, an id twice.
    let three = ["screentext.a", "screentext.b", "screentext.c"].map { action($0) }
    #expect(!UtilityAction.problems(three, feature: "screentext").isEmpty)
    #expect(!UtilityAction.problems([action("tasks.copy")], feature: "screentext").isEmpty)
    #expect(!UtilityAction.problems([action("screentext.")], feature: "screentext").isEmpty)
    #expect(!UtilityAction.problems([action("screentext.copy"), action("screentext.copy")], feature: "screentext").isEmpty)
  }

  /// What the shell needs to place and run an action is plain data: what the window must be when it runs, closed for
  /// one that works on the screen, open for one that covers the window, and the permission a warning names.
  @Test
  func anActionSaysWhatTheWindowMustBeAndWhatItNeeds() {
    let copy = UtilityAction(
      id: "screentext.copy", feature: "screentext", symbol: "text.viewfinder", label: "Copy Text",
      help: "Copy text from the screen", window: .closed, permission: .screenRecording
    ) {}
    #expect(copy.window == .closed && copy.permission == .screenRecording && copy.feature == "screentext")
    #expect(action("home.keyboard", window: .open).window == .open)
    #expect(action("screentext.copy").permission == nil)
  }

  /// The action runs what the feature gave.
  @Test
  func performingRunsTheFeaturesAction() {
    final class Runs {
      var count = 0
    }
    let runs = Runs()
    let action = UtilityAction(
      id: "screentext.copy", feature: "screentext", symbol: "text.viewfinder", label: "Copy Text", help: "Copy text",
      window: .closed
    ) { runs.count += 1 }
    action.perform()
    #expect(runs.count == 1)
  }
}
