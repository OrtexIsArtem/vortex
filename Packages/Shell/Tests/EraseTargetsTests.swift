import Foundation
import Testing

@testable import VortexShell

/// Erase Data deletes only a feature's own settings file and folder, whatever its description says.
struct EraseTargetsTests {
  let root = URL(fileURLWithPath: "/data", isDirectory: true)

  @Test
  func aFeatureLosesItsSettingsFileAndItsFolder() {
    #expect(EraseTargets.paths(id: "clipboard", dataFolder: "Clipboard", in: root).map(\.path) == [
      "/data/clipboard.json", "/data/Clipboard",
    ])
    #expect(EraseTargets.paths(id: "timer", dataFolder: nil, in: root).map(\.path) == ["/data/timer.json"])
  }

  /// A folder that isn't one plain name could reach the whole data folder or beyond: it is never deleted.
  @Test(arguments: ["", ".", "..", "../Vortex", "a/b", ".qa", "/Users"])
  func aFolderThatIsNoPlainNameIsLeftAlone(_ folder: String) {
    #expect(EraseTargets.paths(id: "clipboard", dataFolder: folder, in: root).map(\.path) == ["/data/clipboard.json"])
  }

  /// An id that names one of the shell's own files, or isn't a plain name, deletes no settings file.
  @Test(arguments: ["settings", "onboarding", "permissions", "launch", "Settings", "../settings", "a.b", ""])
  func anIdThatNamesAShellFileDeletesNoSettingsFile(_ id: String) {
    #expect(EraseTargets.paths(id: id, dataFolder: nil, in: root).isEmpty)
  }
}
