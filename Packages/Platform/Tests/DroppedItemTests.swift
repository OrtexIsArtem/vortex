import Foundation
import Testing

@testable import VortexPlatform

struct DroppedItemTests {
  @Test
  func filesInTemporaryAndCacheFoldersAreTemporary() {
    #expect(DroppedItem.isTemporary(FileManager.default.temporaryDirectory.appending(path: "a.png")))
    // A screenshot dragged from its floating thumbnail.
    #expect(DroppedItem.isTemporary(URL(fileURLWithPath: "/var/folders/ab/cd/T/TemporaryItems/NSIRD_screencaptureui_1/Screenshot.png")))
    #expect(DroppedItem.isTemporary(URL(fileURLWithPath: "/private/var/folders/ab/cd/C/com.example/cache.png")))
    #expect(DroppedItem.isTemporary(URL(fileURLWithPath: "/Volumes/Disk/.TemporaryItems/folders.501/TemporaryItems/a.zip")))
  }

  @Test
  func filesElsewhereAreNot() {
    #expect(!DroppedItem.isTemporary(URL(fileURLWithPath: "/Users/me/Desktop/Screenshot.png")))
    #expect(!DroppedItem.isTemporary(URL(fileURLWithPath: "/Users/me/StudioProjects/app/last_builds/app.aab")))
    #expect(!DroppedItem.isTemporary(URL(fileURLWithPath: "/tmp/a.ipa")))
  }
}
