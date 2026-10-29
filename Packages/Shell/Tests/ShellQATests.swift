import Foundation
import Testing

@testable import VortexShell

/// `entry kind=…`: each way in, as QA mode reads it.
struct ShellQATests {
  typealias Entry = ShellQA.Entry

  @Test
  func eachKindIsAWayIn() throws {
    #expect(try Entry(["kind": "hover"]) == .hover(ear: nil))
    #expect(try Entry(["kind": "hover", "ear": "timer"]) == .hover(ear: "timer"))
    #expect(try Entry(["kind": "hover", "ear": ""]) == .hover(ear: nil))
    #expect(try Entry(["kind": "leave"]) == .leave)
    #expect(try Entry(["kind": "ear", "id": "timer"]) == .earClick("timer"))
    #expect(try Entry(["kind": "notch"]) == .notchClick)
    #expect(try Entry(["kind": "menubar"]) == .menuBarClick)
    #expect(try Entry(["kind": "menu", "item": "settings"]) == .menu("settings"))
    #expect(try Entry(["kind": "hotkey", "id": "openVortex"]) == .hotkey("openVortex"))
    #expect(try Entry(["kind": "pointer", "inside": "true"]) == .pointer(inside: true))
    #expect(try Entry(["kind": "pointer", "inside": "false"]) == .pointer(inside: false))
    #expect(try Entry(["kind": "outside"]) == .outsideClick)
    #expect(try Entry(["kind": "escape"]) == .escape)
    #expect(try Entry(["kind": "drag"]) == .drag)
  }

  @Test
  func filesGivenToVortexComeFromTheQAOrATemporaryFolder() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "build.ipa")
    #expect(try Entry(["kind": "drop", "file": file.path]) == .drop(URL(fileURLWithPath: file.path)))
    #expect(try Entry(["kind": "open", "file": file.path]) == .open(URL(fileURLWithPath: file.path)))
    #expect(throws: (any Error).self) { try Entry(["kind": "open", "file": "/Users/someone/Desktop/build.ipa"]) }
    #expect(throws: (any Error).self) { try Entry(["kind": "drop", "file": "build.ipa"]) }
  }

  @Test
  func whatAKindNeedsIsChecked() {
    #expect(throws: (any Error).self) { try Entry([:]) }
    #expect(throws: (any Error).self) { try Entry(["kind": "wave"]) }
    #expect(throws: (any Error).self) { try Entry(["kind": "ear"]) }
    #expect(throws: (any Error).self) { try Entry(["kind": "ear", "id": ""]) }
    #expect(throws: (any Error).self) { try Entry(["kind": "menu"]) }
    #expect(throws: (any Error).self) { try Entry(["kind": "hotkey"]) }
    #expect(throws: (any Error).self) { try Entry(["kind": "pointer"]) }
    #expect(throws: (any Error).self) { try Entry(["kind": "pointer", "inside": "yes"]) }
    #expect(throws: (any Error).self) { try Entry(["kind": "drop"]) }
  }
}
