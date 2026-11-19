import SwiftUI
import Testing

@testable import VortexCore

/// The one-click actions features offer as utilities, which the shell places and runs, and the rules they follow.
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

  /// Two actions can't share a shortcut: one press would run both.
  @Test
  func twoActionsOfAFeatureNeverShareAShortcut() {
    func action(_ id: String, shortcut: String?) -> UtilityAction {
      UtilityAction(
        id: id, feature: "screentext", symbol: "text.viewfinder", label: "Copy Text", help: "Copy text", window: .closed,
        shortcut: shortcut
      ) {}
    }
    #expect(UtilityAction.problems([action("screentext.a", shortcut: "a"), action("screentext.b", shortcut: "b")], feature: "screentext").isEmpty)
    #expect(UtilityAction.problems([action("screentext.a", shortcut: nil), action("screentext.b", shortcut: nil)], feature: "screentext").isEmpty)
    #expect(!UtilityAction.problems([action("screentext.a", shortcut: "a"), action("screentext.b", shortcut: "a")], feature: "screentext").isEmpty)
  }

  /// What the shell needs to place and run an action is plain data: what the window must be when it runs (closed for
  /// one that works on the screen, open for one whose screen covers the window, as it is for one that doesn't care),
  /// the shortcut that runs it, and the permission a warning names.
  @Test
  func anActionSaysWhatTheWindowMustBeAndWhatItNeeds() {
    let copy = UtilityAction(
      id: "screentext.copy", feature: "screentext", symbol: "text.viewfinder", label: "Copy Text",
      help: "Copy text from the screen", window: .closed, permission: .screenRecording, shortcut: "copyScreenText"
    ) {}
    #expect(copy.window == .closed && copy.permission == .screenRecording && copy.feature == "screentext")
    #expect(copy.shortcut == "copyScreenText")
    #expect(action("home.keyboard", window: .open).window == .open)
    #expect(action("clock.toggle", window: .unchanged).window == .unchanged)
    #expect(action("screentext.copy").permission == nil && action("screentext.copy").shortcut == nil)
    #expect(copy.info == UtilityActionInfo(id: "screentext.copy", feature: "screentext", window: .closed, shortcut: "copyScreenText"))
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
