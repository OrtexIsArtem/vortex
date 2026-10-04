import AppKit
import VortexShell

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var shell: ShellController?

  func applicationWillFinishLaunching(_ notification: Notification) {
    // Files that launch the app arrive before it finishes launching.
    shell = ShellController()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    shell?.start()
  }

  /// `vortex shelf add <files>` and Open With: the files go to the shelf.
  func application(_ application: NSApplication, open urls: [URL]) {
    shell?.receiveFiles(urls.filter(\.isFileURL))
  }

  func applicationWillTerminate(_ notification: Notification) {
    shell?.saveSettings()
  }
}
