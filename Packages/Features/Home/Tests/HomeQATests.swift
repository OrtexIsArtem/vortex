import Testing
import VortexCore
import VortexPlatform

@testable import FeatureHome

/// QA mode's `home` command sends what the editor's controls send.
@MainActor
struct HomeQATests {
  /// The arguments as the QA channel hands them over: `key=value`, and a bare word as `word: ""`.
  func actions(_ words: String) throws -> [HomeFeature.Action] {
    var arguments: [String: String] = [:]
    for word in words.split(separator: " ") {
      let parts = word.split(separator: "=", maxSplits: 1)
      arguments[String(parts[0])] = parts.count > 1 ? String(parts[1]) : ""
    }
    return try HomeModule.qaActions(arguments)
  }

  @Test
  func aHomeCommandSendsWhatTheEditorSends() throws {
    #expect(try actions("edit") == [.editTapped])
    #expect(try actions("done") == [.doneTapped])
    #expect(try actions("feature id=clipboard") == [.featureTapped("clipboard")])
    #expect(try actions("back") == [.backTapped])
    #expect(try actions("hover id=clipboard.pinned") == [.hovered("clipboard.pinned")])
    #expect(try actions("hover") == [.hovered(nil)])
    #expect(try actions("resize id=shelf.files size=wide") == [.sizeTapped("shelf.files", .wide)])
    #expect(try actions("add id=clipboard.pinned") == [.addTapped("clipboard.pinned")])
    #expect(
      try actions("add id=clipboard.pinned size=medium")
        == [.sizeTapped("clipboard.pinned", .medium), .addTapped("clipboard.pinned")]
    )
    #expect(try actions("remove id=shelf.files") == [.removeTapped("shelf.files")])
    #expect(try actions("move id=shelf.files column=2 row=1") == [.dropped("shelf.files", column: 2, row: 1)])
  }

  @Test
  func aHomeCommandWithoutWhatItNeedsIsRefused() {
    #expect(throws: QAError.self) { try actions("resize id=shelf.files size=huge") }
    #expect(throws: QAError.self) { try actions("resize id=shelf.files") }
    #expect(throws: QAError.self) { try actions("move id=shelf.files column=two row=1") }
    #expect(throws: QAError.self) { try actions("remove") }
    #expect(throws: QAError.self) { try actions("feature") }
    #expect(throws: QAError.self) { try actions("edit done") }
    #expect(throws: QAError.self) { try actions("dance") }
  }

  /// The state section `home`: the layout, what shows, the editor, the copy and the requests, as plain words.
  @Test
  func theStateSectionTellsTheLayoutAndTheEditor() {
    var state = HomeFeature.State()
    state.$saved.withLock { layout in
      var away = Placement(widget: "tasks.list", size: .medium, column: 2, row: 1)
      away.isAway = true
      layout = HomeLayout(
        notchRow: "timer.timer",
        placed: [Placement(widget: "clipboard.history", size: .large, column: 0, row: 0), away]
      )
    }
    state.widgets = [
      HomeWidgetInfo(id: "timer.timer", feature: "timer", place: .notchRow, name: "Timer", featureName: "Timer", featureSymbol: "timer"),
      HomeWidgetInfo(id: "clipboard.history", feature: "clipboard", place: .grid([.large]), name: "History", featureName: "Clipboard", featureSymbol: "doc"),
    ]
    state.isEditing = true
    state.panel = .feature("clipboard")
    state.preview = .noRoom("clipboard.pinned")
    let section = HomeModule.QAState(state)
    #expect(section.notchRow == "timer.timer")
    #expect(section.placed == ["clipboard.history large (0,0)", "tasks.list medium (2,1) away"])
    #expect(section.visible == ["clipboard.history"])
    #expect(section.widgets == ["timer.timer", "clipboard.history"])
    #expect(section.isEditing)
    #expect(section.panel == "feature:clipboard")
    #expect(section.preview == "noRoom clipboard.pinned")
  }
}
