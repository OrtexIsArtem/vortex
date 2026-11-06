import Foundation
import Testing

@testable import VortexPlatform

struct AppVersionTests {
  @Test(arguments: [
    ("0.1.10", "0.1.9"),
    ("0.2", "0.1.9"),
    ("1.0", "0.9.9"),
    ("0.1.2", "0.1.1"),
    ("0.1.2.1", "0.1.2"),
    ("0.1.2", ""),
  ])
  func newerVersionsAreComparedAsNumbers(newer: String, older: String) {
    #expect(AppVersion.isNewer(newer, than: older))
    #expect(!AppVersion.isNewer(older, than: newer))
  }

  @Test(arguments: [("1.0", "1.0.0"), ("0.1.2", "0.1.2"), ("", "0"), ("0.1.2b", "0.1.2")])
  func theSameVersionIsNotNewer(lhs: String, rhs: String) {
    #expect(!AppVersion.isNewer(lhs, than: rhs))
    #expect(!AppVersion.isNewer(rhs, than: lhs))
  }

  @Test
  func theFullVersionNamesTheBuild() {
    #expect(AppVersion(short: "0.1.2", build: "17").full == "0.1.2 (17)")
  }
}

/// The move to /Applications, on temporary folders that stand in for /Applications, Downloads and the Trash.
struct AppMoverTests {
  /// A temporary folder with Applications, Downloads and Trash in it, removed when the test ends.
  final class Folders {
    let root = FileManager.default.temporaryDirectory.appending(path: "vortex-move-\(UUID().uuidString)")
    var applications: URL { root.appending(path: "Applications") }
    var downloads: URL { root.appending(path: "Downloads") }
    var trashFolder: URL { root.appending(path: "Trash") }
    var installed: URL { applications.appending(path: "Vortex.app") }
    var downloaded: URL { downloads.appending(path: "Vortex.app") }

    init() throws {
      for folder in [applications, downloads, trashFolder] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      }
    }

    deinit {
      // A test may leave a file it made unreadable.
      if let items = FileManager.default.enumerator(atPath: root.path) {
        for case let item as String in items {
          chmod(root.path + "/" + item, 0o755)
        }
      }
      try? FileManager.default.removeItem(at: root)
    }

    /// An app bundle whose file `which` says which copy it is.
    func makeApp(at url: URL, which: String, quarantined: Bool = false) throws {
      let contents = url.appending(path: "Contents")
      try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
      try Data(which.utf8).write(to: contents.appending(path: "which"))
      guard quarantined else { return }
      let value = "0083;6716c9a0;Safari;"
      for path in [url.path, contents.path, contents.appending(path: "which").path] {
        #expect(setxattr(path, "com.apple.quarantine", value, value.utf8.count, 0, XATTR_NOFOLLOW) == 0)
      }
    }

    func which(_ app: URL) -> String? {
      (try? Data(contentsOf: app.appending(path: "Contents/which"))).map { String(decoding: $0, as: UTF8.self) }
    }

    /// What the stand-in Trash holds, by which copy each item is.
    var trashed: [String] {
      ((try? FileManager.default.contentsOfDirectory(at: trashFolder, includingPropertiesForKeys: nil)) ?? [])
        .compactMap(which).sorted()
    }

    /// Moves into the stand-in Trash under a name of its own, as the Trash keeps two items of one name.
    var mover: AppMover {
      AppMover { [trashFolder] url in
        let trashed = trashFolder.appending(path: "\(UUID().uuidString)-\(url.lastPathComponent)")
        try FileManager.default.moveItem(at: url, to: trashed)
        return trashed
      }
    }
  }

  static func isQuarantined(_ path: String) -> Bool {
    getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
  }

  @Test
  func theNewAppTakesTheOldOnesPlaceWithoutQuarantineAndTheOldOneGoesToTheTrash() throws {
    let folders = try Folders()
    try folders.makeApp(at: folders.installed, which: "old")
    try folders.makeApp(at: folders.downloaded, which: "new", quarantined: true)
    #expect(Self.isQuarantined(folders.downloaded.path))

    try folders.mover.install(folders.downloaded, at: folders.installed)

    #expect(folders.which(folders.installed) == "new")
    #expect(folders.trashed == ["old"])
    // Moved, not copied: nothing stays in Downloads.
    #expect(!FileManager.default.fileExists(atPath: folders.downloaded.path))
    for path in [folders.installed.path, folders.installed.appending(path: "Contents/which").path] {
      #expect(!Self.isQuarantined(path))
    }
  }

  @Test
  func withoutAnOldAppNothingGoesToTheTrash() throws {
    let folders = try Folders()
    try folders.makeApp(at: folders.downloaded, which: "new")
    try folders.mover.install(folders.downloaded, at: folders.installed)
    #expect(folders.which(folders.installed) == "new")
    #expect(folders.trashed.isEmpty)
  }

  /// macOS's App Management may refuse (EPERM) to move another app's bundle: then nothing changes at all.
  @Test
  func anOldAppThatCantGoLeavesEverythingAsItWas() throws {
    let folders = try Folders()
    try folders.makeApp(at: folders.installed, which: "old")
    try folders.makeApp(at: folders.downloaded, which: "new", quarantined: true)
    let refusing = AppMover { _ in throw POSIXError(.EPERM) }
    #expect(throws: POSIXError.self) { try refusing.install(folders.downloaded, at: folders.installed) }
    #expect(folders.which(folders.installed) == "old")
    #expect(folders.which(folders.downloaded) == "new")
    #expect(Self.isQuarantined(folders.downloaded.path))
  }

  /// A Trash that took the old app without telling where it went couldn't put it back after a failed landing: the move
  /// stops before the new app moves, and the old one waits in the Trash, where the user can put it back.
  @Test
  func aTrashThatDoesntTellWhereTheOldAppWentStopsTheMove() throws {
    let folders = try Folders()
    try folders.makeApp(at: folders.installed, which: "old")
    try folders.makeApp(at: folders.downloaded, which: "new")
    let silent = AppMover { [trashFolder = folders.trashFolder] url in
      try FileManager.default.moveItem(at: url, to: trashFolder.appending(path: url.lastPathComponent))
      return nil
    }
    #expect(throws: AppMoveError.trashedOutOfSight) { try silent.install(folders.downloaded, at: folders.installed) }
    #expect(folders.trashed == ["old"])
    #expect(folders.which(folders.downloaded) == "new")
    #expect(!FileManager.default.fileExists(atPath: folders.installed.path))
  }

  @Test
  func aNewAppThatCantLandBringsTheOldOneBack() throws {
    let folders = try Folders()
    try folders.makeApp(at: folders.installed, which: "old")
    // Gone meanwhile: the rename fails after the old app went to the Trash.
    #expect(throws: POSIXError.self) { try folders.mover.install(folders.downloaded, at: folders.installed) }
    #expect(folders.which(folders.installed) == "old")
    #expect(folders.trashed.isEmpty)
  }

  @Test
  func aCopyThatStopsHalfwayIsRemovedAndTheOldOneComesBack() throws {
    let folders = try Folders()
    try folders.makeApp(at: folders.installed, which: "old")
    try folders.makeApp(at: folders.downloaded, which: "new")
    let unreadable = folders.downloaded.appending(path: "Contents/unreadable")
    try Data("x".utf8).write(to: unreadable)
    #expect(chmod(unreadable.path, 0) == 0)

    #expect(throws: (any Error).self) {
      try folders.mover.install(folders.downloaded, at: folders.installed, copying: true)
    }
    #expect(folders.which(folders.installed) == "old")
    #expect(folders.trashed.isEmpty)
    #expect(folders.which(folders.downloaded) == "new")
  }

  @Test
  func aCopiedSourceGoesToTheTrashUnlessItIsTheTranslocatedPath() throws {
    let folders = try Folders()
    try folders.makeApp(at: folders.downloaded, which: "new")
    try folders.mover.install(folders.downloaded, at: folders.installed, copying: true)
    #expect(folders.which(folders.installed) == "new")
    #expect(folders.trashed == ["new"])

    let again = try Folders()
    try again.makeApp(at: again.installed, which: "old")
    try again.makeApp(at: again.downloaded, which: "new")
    try again.mover.install(again.downloaded, at: again.installed, copying: true, trashesCopiedSource: false)
    #expect(again.which(again.installed) == "new")
    #expect(again.which(again.downloaded) == "new")
    #expect(again.trashed == ["old"])
  }

  /// Under App Translocation the original moves, so no copy stays in Downloads; without it, the translocated path is
  /// copied and left alone.
  @Test
  func aTranslocatedCopyMovesItsOriginalOrElseIsCopied() throws {
    let folders = try Folders()
    let translocated = folders.root.appending(path: "AppTranslocation/d/Vortex.app")
    try folders.makeApp(at: translocated, which: "translocated")
    try folders.makeApp(at: folders.downloaded, which: "new")
    let withOriginal = AppCopy(
      bundle: translocated, original: folders.downloaded, isTranslocated: true, bundleID: "vortex", version: "0.1.2"
    )
    try folders.mover.move(withOriginal, to: folders.installed)
    #expect(folders.which(folders.installed) == "new")
    #expect(!FileManager.default.fileExists(atPath: folders.downloaded.path))
    #expect(folders.which(translocated) == "translocated")

    let unknown = try Folders()
    let hidden = unknown.root.appending(path: "AppTranslocation/d/Vortex.app")
    try unknown.makeApp(at: hidden, which: "translocated")
    let withoutOriginal = AppCopy(bundle: hidden, isTranslocated: true, bundleID: "vortex", version: "0.1.2")
    try unknown.mover.move(withoutOriginal, to: unknown.installed)
    #expect(unknown.which(unknown.installed) == "translocated")
    #expect(unknown.which(hidden) == "translocated")
    #expect(unknown.trashed.isEmpty)
  }

  @Test
  func anAppIsReadFromItsInfoPlist() throws {
    let folders = try Folders()
    try folders.makeApp(at: folders.installed, which: "old")
    let info: [String: Any] = ["CFBundleIdentifier": "io.github.ortexisartem.vortex", "CFBundleShortVersionString": "0.1.1"]
    let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try plist.write(to: folders.installed.appending(path: "Contents/Info.plist"))
    #expect(InstalledApp(at: folders.installed) == InstalledApp(bundleID: "io.github.ortexisartem.vortex", version: "0.1.1"))
    // Something there that isn't an app, and nothing there.
    try folders.makeApp(at: folders.downloaded, which: "new")
    #expect(InstalledApp(at: folders.downloaded) == InstalledApp(bundleID: nil, version: nil))
    #expect(InstalledApp(at: folders.applications.appending(path: "Missing.app")) == nil)
  }

  /// Security's functions are looked up at runtime: a plain path isn't translocated, and the lookup doesn't crash.
  @Test
  func aPlainPathIsNotTranslocated() {
    let result = Translocation.original(of: URL(fileURLWithPath: "/System/Applications/Calculator.app"))
    #expect(!result.isTranslocated)
    #expect(result.original == nil)
  }
}

#if DEBUG
  /// A QA run never moves itself: it looks kept in /Applications, and a move is refused and logged.
  struct QAAppInstallClientTests {
    @Test
    func aQARunNeverMoves() async {
      let client = AppInstallClient.qa
      let applications = URL(fileURLWithPath: "/Applications/Vortex.app")
      #expect(client.current()?.location == applications)
      #expect(client.app(applications) == nil)
      let downloaded = AppCopy(bundle: URL(fileURLWithPath: "/tmp/Vortex.app"), bundleID: "vortex", version: "0.1.2")
      #expect(throws: QAError.self) { try client.move(downloaded, applications) }
      // The relaunch from /Applications is logged, never run.
      func relaunches() -> Int {
        QALog.events.value.filter { $0.client == "system" && $0.event == "relaunchFrom" }.count
      }
      let before = relaunches()
      await SystemClient.qa.relaunchFrom(applications)
      #expect(relaunches() == before + 1)
    }
  }
#endif
