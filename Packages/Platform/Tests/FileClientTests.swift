import ConcurrencyExtras
import Foundation
import Testing

@testable import VortexPlatform

/// Runs the live file client against a temporary folder.
struct FileClientTests {
  let files = FileClient.liveValue
  let root = FileManager.default.temporaryDirectory.appending(path: "vortex-tests-\(UUID().uuidString)")

  init() throws {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  /// A name shows as Finder shows it, but an extension Finder hides stays: a build's .aab matters.
  @Test
  func aNameShowsAsInFinderWithItsExtension() throws {
    defer { try? FileManager.default.removeItem(at: root) }
    var file = root.appending(path: "app-release.aab")
    try Data(count: 3).write(to: file)
    var hidden = URLResourceValues()
    hidden.hasHiddenExtension = true
    try file.setResourceValues(hidden)
    #expect(FileName.shown(file) == "app-release.aab")
    let folder = root.appending(path: "builds", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    #expect(FileName.shown(folder) == "builds")
    // A folder macOS names in the app's language reads as Finder names it, here in the language of `swift test`.
    let downloads = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory)
    #expect(FileName.shown(downloads) == FileManager.default.displayName(atPath: downloads.path))
    #expect(FileName.shown(root.appending(path: "missing.ipa")) == "missing.ipa")
  }

  @Test
  func infoNoticesAFileDeletedMeanwhile() async throws {
    let file = root.appending(path: "build.ipa")
    try Data(count: 3).write(to: file)
    #expect(await files.info(file) == FileInfo(size: 3, isDirectory: false))
    try FileManager.default.removeItem(at: file)
    #expect(await files.info(file) == nil)
    try FileManager.default.removeItem(at: root)
  }

  /// Whether this user may run a file, through a link too; a folder never counts.
  @Test
  func infoSaysWhetherAFileRuns() async throws {
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "claude")
    try Data("#!/bin/sh\n".utf8).write(to: file)
    #expect(await files.info(file)?.isExecutable == false)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    #expect(await files.info(file)?.isExecutable == true)
    let link = root.appending(path: "link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    #expect(await files.info(link)?.isExecutable == true)
    #expect(await files.info(root)?.isExecutable == false)
  }

  @Test
  func theWatcherReportsNewFilesAndTheFilesOfFoldersMovedIn() async throws {
    let reported = LockIsolated<Set<String>>([])
    let watching = Task {
      for await url in files.changes(root) {
        reported.withValue { _ = $0.insert(url.lastPathComponent) }
      }
    }
    defer {
      watching.cancel()
      try? FileManager.default.removeItem(at: root)
    }
    try await Task.sleep(for: .milliseconds(500))

    try Data(count: 1).write(to: root.appending(path: "direct.ipa"))
    let export = FileManager.default.temporaryDirectory.appending(path: "vortex-export-\(UUID().uuidString)")
    for path in ["Export/moved.ipa", "Export/.hidden/secret.ipa", "Export/Old.app/Contents/inside.ipa"] {
      try FileManager.default.createDirectory(
        at: export.appending(path: path).deletingLastPathComponent(), withIntermediateDirectories: true
      )
      try Data(count: 1).write(to: export.appending(path: path))
    }
    try FileManager.default.moveItem(at: export.appending(path: "Export"), to: root.appending(path: "Export"))
    try? FileManager.default.removeItem(at: export)

    for _ in 0..<40 where !reported.value.isSuperset(of: ["direct.ipa", "moved.ipa"]) {
      try await Task.sleep(for: .milliseconds(100))
    }
    try await Task.sleep(for: .milliseconds(500))
    #expect(reported.value.isSuperset(of: ["direct.ipa", "moved.ipa"]))
    #expect(!reported.value.contains("secret.ipa"))
    #expect(!reported.value.contains("inside.ipa"))
  }
}
