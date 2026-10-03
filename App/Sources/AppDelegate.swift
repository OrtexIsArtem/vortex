import AppKit
import VortexShell

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var shell: ShellController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let shell = ShellController()
    shell.start()
    self.shell = shell
  }

  func applicationWillTerminate(_ notification: Notification) {
    shell?.saveSettings()
  }
}
