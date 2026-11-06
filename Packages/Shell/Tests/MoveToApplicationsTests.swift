import AppKit
import ComposableArchitecture
import Foundation
import Testing
import VortexPlatform

@testable import VortexShell

/// The offer a release build makes at launch to move itself to /Applications: where it runs, the versions,
/// "Don't ask again", and what each answer does, with substituted clients.
@MainActor
struct MoveToApplicationsTests {
  let home = URL(fileURLWithPath: "/Users/someone")
  let vortex = "io.github.ortexisartem.vortex"
  /// "ask:<replacesOlder>", "failure", "move:<from>", "decline", "relaunch:<path>".
  let calls = CallLog()

  func copy(_ path: String, original: String? = nil, version: String = "0.1.2") -> AppCopy {
    AppCopy(
      bundle: URL(fileURLWithPath: path),
      original: original.map { URL(fileURLWithPath: $0) },
      isTranslocated: original != nil,
      bundleID: vortex,
      version: version
    )
  }

  func decide(_ copy: AppCopy, installed: InstalledApp? = nil, isDeclined: Bool = false) -> MoveToApplications.Decision {
    MoveToApplications.decide(copy, installed: installed, home: home, isDeclined: isDeclined)
  }

  // MARK: - The decision

  @Test(arguments: [
    "/Applications/Vortex.app",
    "/Applications/Utilities/Vortex.app",
    "/Users/someone/Applications/Vortex.app",
    "/System/Volumes/Data/Applications/Vortex.app",
  ])
  func aCopyKeptInTheApplicationsFoldersStartsWithoutAsking(path: String) {
    #expect(decide(copy(path)) == .run)
  }

  @Test(arguments: [
    "/Users/someone/Downloads/Vortex.app",
    "/Users/someone/Desktop/Vortex.app",
    "/Volumes/Vortex/Vortex.app",
    "/Applications Old/Vortex.app",
    "/Users/someone/ApplicationsBackup/Vortex.app",
    "/Users/other/Applications/Vortex.app",
  ])
  func aCopyKeptElsewhereAsks(path: String) {
    #expect(decide(copy(path)) == .ask(replacesOlder: false))
  }

  /// Under App Translocation the app runs from a random path; where the user keeps its original is what counts.
  @Test
  func underAppTranslocationTheOriginalCounts() {
    let translocated = "/private/var/folders/xy/T/AppTranslocation/1F2E/d/Vortex.app"
    #expect(decide(copy(translocated, original: "/Applications/Vortex.app")) == .run)
    #expect(decide(copy(translocated, original: "/Users/someone/Downloads/Vortex.app")) == .ask(replacesOlder: false))
    // macOS didn't say where the original is: the translocated path is outside the Applications folders.
    var unknown = copy(translocated)
    unknown.isTranslocated = true
    #expect(decide(unknown) == .ask(replacesOlder: false))
  }

  @Test
  func aVortexOfTheSameOrAnOlderVersionInApplicationsGoesToTheTrashANewerOneIsLeftAndRun() {
    let downloaded = copy("/Users/someone/Downloads/Vortex.app", version: "0.1.10")
    func installed(_ version: String?) -> InstalledApp { InstalledApp(bundleID: vortex, version: version) }
    #expect(decide(downloaded, installed: installed("0.1.9")) == .ask(replacesOlder: true))
    #expect(decide(downloaded, installed: installed("0.1.10")) == .ask(replacesOlder: true))
    #expect(decide(downloaded, installed: installed(nil)) == .ask(replacesOlder: true))
    #expect(decide(downloaded, installed: installed("0.1.11")) == .run)
    #expect(decide(downloaded, installed: installed("0.2")) == .run)
  }

  /// Another app named Vortex.app never goes to the Trash for this one: Vortex just runs.
  @Test
  func anotherAppAtTheDestinationIsLeftAlone() {
    let downloaded = copy("/Users/someone/Downloads/Vortex.app")
    #expect(decide(downloaded, installed: InstalledApp(bundleID: "com.example.vortex", version: "0.0.1")) == .run)
    #expect(decide(downloaded, installed: InstalledApp(bundleID: nil, version: nil)) == .run)
  }

  @Test
  func dontAskAgainIsNeverAskedAgain() {
    #expect(decide(copy("/Users/someone/Downloads/Vortex.app"), isDeclined: true) == .run)
  }

  // MARK: - The answers

  /// `meanwhile`: what /Applications holds once the alert is answered, when that differs from `installed`.
  func offer(
    from path: String = "/Users/someone/Downloads/Vortex.app",
    installed: InstalledApp? = nil,
    meanwhile: InstalledApp?? = nil,
    answer: MoveToApplications.Answer? = nil,
    moveFails: Bool = false
  ) -> Bool {
    let current = copy(path)
    let reads = LockIsolated(0)
    return withDependencies {
      $0.appInstallClient.current = { current }
      $0.appInstallClient.app = { url in
        #expect(url.path == "/Applications/Vortex.app")
        let read = reads.withValue { count -> Int in
          count += 1
          return count
        }
        if read > 1, let meanwhile { return meanwhile }
        return installed
      }
      $0.appInstallClient.isMoveDeclined = { false }
      $0.appInstallClient.declineMove = { [calls] in calls.record("decline") }
      $0.appInstallClient.move = { [calls] copy, destination in
        calls.record("move:\(copy.location.path)->\(destination.path)")
        if moveFails { throw POSIXError(.EPERM) }
      }
      if let answer {
        $0.moveAlert.ask = { [calls] replacesOlder in
          calls.record("ask:\(replacesOlder)")
          return answer
        }
      }
      $0.moveAlert.showFailure = { [calls] in calls.record("failure") }
      $0.systemClient.relaunchFrom = { [calls] app in calls.record("relaunch:\(app.path)") }
    } operation: {
      MoveToApplications().offer(home: home)
    }
  }

  @Test
  func notNowWithDontAskAgainRemembersItAndRunsFromWhereItIs() async {
    #expect(!offer(answer: .notNow(dontAskAgain: true)))
    #expect(await calls.next() == "ask:false")
    #expect(await calls.next() == "decline")
    #expect(calls.untaken.isEmpty)
  }

  @Test
  func notNowAloneAsksAgainNextTime() async {
    #expect(!offer(answer: .notNow(dontAskAgain: false)))
    #expect(await calls.next() == "ask:false")
    #expect(calls.untaken.isEmpty)
  }

  @Test
  func movingPutsTheAppInApplicationsThenQuitsAndOpensItFromThere() async {
    let installed = InstalledApp(bundleID: vortex, version: "0.1.1")
    #expect(offer(installed: installed, answer: .move))
    #expect(await calls.next() == "ask:true")
    #expect(await calls.next() == "move:/Users/someone/Downloads/Vortex.app->/Applications/Vortex.app")
    #expect(await calls.next() == "relaunch:/Applications/Vortex.app")
  }

  @Test
  func aFailedMoveSaysSoAndRunsOnFromWhereItIs() async {
    #expect(!offer(answer: .move, moveFails: true))
    #expect(await calls.next() == "ask:false")
    #expect(await calls.next() == "move:/Users/someone/Downloads/Vortex.app->/Applications/Vortex.app")
    #expect(await calls.next() == "failure")
    #expect(await calls.next(timeout: .milliseconds(200)) == nil)
  }

  /// The alert may stay up for minutes: after Move, /Applications is read again. A newer Vortex or another app that
  /// came meanwhile stays there, and Vortex just runs; an older Vortex goes to the Trash as any would.
  @Test
  func whatCameToApplicationsWhileTheAlertWasUpDecidesAgain() async {
    #expect(!offer(meanwhile: InstalledApp(bundleID: vortex, version: "0.2"), answer: .move))
    #expect(await calls.next() == "ask:false")
    #expect(!offer(meanwhile: InstalledApp(bundleID: "com.example.vortex", version: "1.0"), answer: .move))
    #expect(await calls.next() == "ask:false")
    #expect(await calls.next(timeout: .milliseconds(200)) == nil)

    #expect(offer(meanwhile: InstalledApp(bundleID: vortex, version: "0.1.1"), answer: .move))
    #expect(await calls.next() == "ask:false")
    #expect(await calls.next() == "move:/Users/someone/Downloads/Vortex.app->/Applications/Vortex.app")
    #expect(await calls.next() == "relaunch:/Applications/Vortex.app")
  }

  /// Kept in /Applications, or with a newer Vortex there, nothing is asked: the alert isn't substituted here, and
  /// asking would fail the test.
  @Test
  func nothingIsAskedWhenTheDecisionIsToRun() {
    #expect(!offer(from: "/Applications/Vortex.app"))
    #expect(!offer(installed: InstalledApp(bundleID: vortex, version: "9.0")))
    #expect(calls.all.isEmpty)
  }

  /// The question's buttons and checkbox; its words are in the String Catalog, which tests don't read.
  @Test
  func theQuestionOffersMoveByDefaultNotNowOnEscAndAnUntickedCheckbox() {
    let alert = MoveAlerts.makeQuestion(replacesOlder: true)
    #expect(alert.buttons.count == 2)
    #expect(alert.buttons[1].keyEquivalent == "\u{1b}")
    #expect(alert.showsSuppressionButton)
    #expect(alert.suppressionButton?.state == .off)
    #expect(MoveAlerts.makeQuestion(replacesOlder: false).informativeText.count < alert.informativeText.count)
  }
}
