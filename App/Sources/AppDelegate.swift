import AppKit
import VortexShell

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var shell: ShellController?

  func applicationWillFinishLaunching(_ notification: Notification) {
    quitOtherInstances()
    // Files that launch the app arrive before it finishes launching.
    shell = ShellController()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    shell?.start()
  }

  /// `vortex shelf add <files>` and `open -a Vortex <files>`: the files go to the shelf.
  func application(_ application: NSApplication, open urls: [URL]) {
    shell?.receiveFiles(urls.filter(\.isFileURL))
  }

  func applicationWillTerminate(_ notification: Notification) {
    shell?.saveSettings()
  }

  /// A Vortex started while another runs, such as a build run from Xcode next to one opened before it, takes over: two
  /// would overwrite each other's data and both show in the notch, and the older one would keep the MCP port. The
  /// others are asked to quit, which saves their settings, and stopped if they are still there after 2 s; this one
  /// reads the settings after that.
  private func quitOtherInstances() {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
      .filter { $0.processIdentifier != getpid() }
    guard !others.isEmpty else { return }
    for app in others { app.terminate() }
    if !waitUntilGone(others, seconds: 2) {
      for app in others { app.forceTerminate() }
      _ = waitUntilGone(others, seconds: 1)
    }
  }

  /// Whether the apps are gone before the time is up. Asks the system about the processes themselves:
  /// `isTerminated` changes only once the run loop runs, and running it now could hand over files before the shell
  /// exists.
  private func waitUntilGone(_ apps: [NSRunningApplication], seconds: TimeInterval) -> Bool {
    let deadline = Date.now.addingTimeInterval(seconds)
    func anyRunning() -> Bool { apps.contains { kill($0.processIdentifier, 0) == 0 } }
    while anyRunning(), Date.now < deadline {
      usleep(50_000)
    }
    return !anyRunning()
  }
}
