import Foundation
import Testing

@testable import VortexPlatform

struct RelaunchTests {
  @Test
  func theHelperWaitsForThisProcessThenOpensTheApp() {
    let arguments = Relaunch.arguments(pid: 4242, bundlePath: "/Applications/Vortex.app")
    #expect(arguments.count == 3)
    #expect(arguments[0] == "-c")
    #expect(arguments[1].contains("while kill -0 4242 2>/dev/null"))
    #expect(arguments[1].hasSuffix("open \"$0\""))
    #expect(arguments[2] == "/Applications/Vortex.app")
  }

  /// A quit that was cancelled leaves the process running: the helper gives up after about 10 s and opens nothing.
  @Test
  func theHelperGivesUpAfterAboutTenSecondsWithoutOpening() throws {
    let script = Relaunch.arguments(pid: 4242, bundlePath: "/Applications/Vortex.app")[1]
    #expect(Relaunch.checks == 100)
    #expect(script.contains("[ $n -gt 100 ] && exit 0; sleep 0.1"))
    // Giving up exits inside the loop, before `open`.
    let exit = try #require(script.range(of: "exit 0"))
    let open = try #require(script.range(of: "open"))
    #expect(exit.lowerBound < open.lowerBound)
  }

  @Test
  func theBundlePathNeverGoesIntoTheScript() {
    let path = "/tmp/a \"b\" $(c)/Vortex.app"
    let arguments = Relaunch.arguments(pid: 1, bundlePath: path)
    #expect(!arguments[1].contains(path))
    #expect(arguments[2] == path)
  }

  /// The reopen after System Settings' «Quit & Reopen» uses this helper: `open` without `-n`, so a Vortex System Settings
  /// opened first is not doubled.
  @Test
  func theHelperOpensWithoutANewInstance() {
    let script = Relaunch.arguments(pid: 4242, bundlePath: "/Applications/Vortex.app")[1]
    #expect(!script.contains("-n"))
    #expect(script.components(separatedBy: "open").count == 2)
  }
}

/// Which quits bring Vortex back by itself: only the one System Settings asks for after «Quit & Reopen».
struct QuitRequestTests {
  @Test
  func systemSettingsQuitReopens() {
    #expect(QuitRequest.reopens(senderBundleID: "com.apple.systempreferences"))
  }

  @Test(arguments: [
    // Vortex's own Quit and ⌘Q: no Apple event.
    nil,
    // Logout and shutdown.
    "com.apple.loginwindow",
    // A newer Vortex taking over, and QA's build of it.
    "io.github.ortexisartem.vortex",
    "io.github.ortexisartem.vortex.check",
    // Any other app, and near misses of System Settings' id.
    "com.apple.ActivityMonitor",
    "com.apple.Terminal",
    "com.apple.systempreferences.extension",
    "COM.APPLE.SYSTEMPREFERENCES",
    "",
  ] as [String?])
  func everyOtherQuitJustQuits(sender: String?) {
    #expect(!QuitRequest.reopens(senderBundleID: sender))
  }

  /// Outside an Apple event, as under `swift test`, there is no sender, so nothing reopens.
  @MainActor
  @Test
  func withNoQuitEventThereIsNoSender() {
    #expect(QuitRequest.currentSenderBundleID() == nil)
  }
}

#if DEBUG
  /// In a QA run the reopen after System Settings' quit is logged and never run: no helper outlives the run.
  struct QASystemClientTests {
    @Test
    func theReopenIsLoggedNeverRun() {
      func count() -> Int {
        QALog.events.value.filter { $0.client == "system" && $0.event == "reopenAfterQuit" }.count
      }
      let before = count()
      SystemClient.qa.reopenAfterQuit()
      #expect(count() == before + 1)
    }
  }
#endif
