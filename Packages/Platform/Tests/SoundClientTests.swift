import Foundation
import Testing

@testable import VortexPlatform

struct SoundClientTests {
  @Test
  func listsSoundFilesByNameSortedWithoutHiddenFiles() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "sounds-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for name in ["Tink.aiff", "Basso.aiff", "glass.aiff", ".DS_Store"] {
      try Data().write(to: folder.appending(path: name))
    }
    #expect(SystemSounds.names(in: folder) == ["Basso", "glass", "Tink"])
  }

  @Test
  func aMissingFolderHasNoSounds() {
    #expect(SystemSounds.names(in: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")).isEmpty)
  }
}
