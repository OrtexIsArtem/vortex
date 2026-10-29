import Foundation
import Testing

@testable import VortexPlatform

/// Where QA may write: inside its own folder or a temporary one, never in the user's data folder, whatever `..`, links
/// or letter case say.
struct QAPathsTests {
  let root: URL
  let allowed: URL
  let forbidden: URL

  init() throws {
    root = FileManager.default.temporaryDirectory.appending(path: "vortex-qa-paths-\(UUID().uuidString)")
    allowed = root.appending(path: "Vortex QA/A")
    forbidden = root.appending(path: "Vortex")
    try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: forbidden, withIntermediateDirectories: true)
  }

  func isSafe(_ path: String) -> Bool {
    QAPaths.isSafe(URL(fileURLWithPath: path), allowed: [allowed], forbidden: [forbidden])
  }

  func cleanUp() {
    try? FileManager.default.removeItem(at: root)
  }

  @Test
  func insideTheRunsFolderIsSafe() {
    #expect(isSafe(allowed.path))
    #expect(isSafe(allowed.appending(path: "state.json").path))
    #expect(isSafe(allowed.appending(path: "new/folder/reply.json").path))
    cleanUp()
  }

  @Test
  func theUsersFolderAndEverythingElseIsNot() {
    #expect(!isSafe(forbidden.appending(path: "vortex.sqlite").path))
    #expect(!isSafe(forbidden.path))
    #expect(!isSafe(root.path))
    #expect(!isSafe(root.appending(path: "Vortex QA").path))
    #expect(!isSafe("/Users/someone/Desktop/file.png"))
    cleanUp()
  }

  @Test
  func aFolderWhoseNameStartsTheSameIsAnotherFolder() {
    // "Vortex QA/A" must not let "Vortex QA/AB" in, nor "Vortex" let "Vortex QA" out.
    #expect(!isSafe(root.appending(path: "Vortex QA/AB/file").path))
    #expect(QAPaths.isSafe(
      URL(fileURLWithPath: root.appending(path: "Vortex QA/A/x").path),
      allowed: [root.appending(path: "Vortex QA")],
      forbidden: [forbidden]
    ))
    cleanUp()
  }

  @Test
  func dotDotCannotClimbOut() {
    #expect(!isSafe(allowed.path + "/../../Vortex/vortex.sqlite"))
    #expect(!isSafe(allowed.path + "/missing/../../../Vortex/settings.json"))
    #expect(isSafe(allowed.path + "/missing/../reply.json"))
    #expect(isSafe(allowed.path + "/./reply.json"))
    cleanUp()
  }

  @Test
  func linksAreFollowed() throws {
    let link = allowed.appending(path: "link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: forbidden)
    #expect(!isSafe(link.appending(path: "vortex.sqlite").path))
    // `..` after a link climbs from where the link points, as the file system does.
    let outside = allowed.appending(path: "outside")
    try FileManager.default.createSymbolicLink(at: outside, withDestinationURL: forbidden.appending(path: "sub"))
    try FileManager.default.createDirectory(at: forbidden.appending(path: "sub"), withIntermediateDirectories: true)
    #expect(!isSafe(outside.path + "/../settings.json"))
    cleanUp()
  }

  @Test
  func caseDoesNotGetAroundIt() {
    let shouted = forbidden.deletingLastPathComponent().appending(path: "VORTEX/vortex.sqlite")
    #expect(!isSafe(shouted.path))
    cleanUp()
  }

  @Test
  func theStringCheckWantsAnAbsolutePath() {
    #expect(!QAPaths.isSafe("reply.json"))
    #expect(!QAPaths.isSafe(""))
    #expect(QAPaths.isSafe(FileManager.default.temporaryDirectory.appending(path: "qa-reply.json").path))
    #expect(QAPaths.isSafe("/tmp/qa-reply.json"))
    #expect(!QAPaths.isSafe(QAPaths.userFolder.appending(path: "settings.json").path))
    cleanUp()
  }

  @Test
  func outsideQAModeTheUsersFolderIsNeverSafeThoughItIsTheDataFolder() {
    // In tests DataFolder is the user's folder: it is among the allowed folders and still refused.
    #expect(!QAPaths.isSafe(QAPaths.userFolder.appending(path: ".qa/reply.json").path))
    #expect(!QAPaths.isSafe(QAPaths.userFolder.path))
    cleanUp()
  }
}
