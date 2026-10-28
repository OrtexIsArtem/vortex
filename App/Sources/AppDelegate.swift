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
  /// reads the settings after that. A QA run (`--qa <name>`) has data of its own: it takes over only from the same run
  /// and plain Vortex only from plain Vortex.
  private func quitOtherInstances() {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
      .filter { $0.processIdentifier != getpid() && isSameKind($0) }
    guard !others.isEmpty else { return }
    // Two started at about the same moment would stop each other and leave none: the later one stays, so this one
    // steps aside for a newer one, before it has anything to save.
    let mine = startTime(of: getpid())
    if others.contains(where: { startTime(of: $0.processIdentifier) > mine }) { exit(0) }
    for app in others { app.terminate() }
    if !waitUntilGone(others, seconds: 2) {
      for app in others { app.forceTerminate() }
      _ = waitUntilGone(others, seconds: 1)
    }
  }

  /// The same QA run, or both plain Vortex.
  private func isSameKind(_ app: NSRunningApplication) -> Bool {
    #if DEBUG
      ShellController.isSameQARun(pid: app.processIdentifier)
    #else
      true
    #endif
  }

  /// When a process started, with its pid to settle a tie; the earliest there is when the system doesn't say.
  private func startTime(of pid: pid_t) -> (Int, Int, pid_t) {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var request: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&request, 4, &info, &size, nil, 0) == 0, size > 0 else { return (0, 0, pid) }
    let time = info.kp_proc.p_starttime
    return (time.tv_sec, Int(time.tv_usec), pid)
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
