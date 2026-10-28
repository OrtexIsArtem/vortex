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
}
