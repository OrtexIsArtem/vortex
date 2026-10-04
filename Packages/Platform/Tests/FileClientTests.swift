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

  @Test
  func infoNoticesAFileDeletedMeanwhile() async throws {
    let file = root.appending(path: "build.ipa")
    try Data(count: 3).write(to: file)
    #expect(await files.info(file) == FileInfo(size: 3, isDirectory: false))
    try FileManager.default.removeItem(at: file)
    #expect(await files.info(file) == nil)
    try FileManager.default.removeItem(at: root)
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
