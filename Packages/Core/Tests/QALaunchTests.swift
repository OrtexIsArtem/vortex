import Foundation
import Testing

@testable import VortexCore

/// `--qa <name>` and its options, and the data folder they choose.
struct QALaunchTests {
  func launch(_ words: String...) -> QALaunch {
    QALaunch(arguments: ["/Applications/Vortex.app/Contents/MacOS/Vortex"] + words)
  }

  func isInvalid(_ launch: QALaunch) -> Bool {
    if case .invalid = launch { true } else { false }
  }

  @Test
  func withoutQANothingChanges() {
    #expect(launch() == .none)
    #expect(launch("-NSDocumentRevisionsDebugMode", "YES") == .none)
    #expect(launch("-AppleLanguages", "(uk)").name == nil)
  }

  @Test
  func aNameStartsAQARun() {
    #expect(launch("--qa", "A") == .named("a", .init()))
    #expect(launch("-AppleLanguages", "(uk)", "--qa", "tester-B2").name == "tester-b2")
    #expect(launch("--qa", "1234567890abcdef").name == "1234567890abcdef")
  }

  @Test
  func namesAreKeptInLowercaseSoCaseNeverMakesTwoRuns() {
    // The run's folder is found without regard to case: A and a must be one run, with one name.
    #expect(launch("--qa", "Tester-A").name == "tester-a")
    #expect(launch("--qa", "A") == launch("--qa", "a"))
  }

  @Test
  func theExecutableIsNeverAnArgument() {
    #expect(QALaunch(arguments: ["--qa"]) == .none)
    #expect(QALaunch(arguments: ["--qa", "A"]) == .none)
    #expect(QALaunch(arguments: []) == .none)
  }

  @Test
  func namesAreOneToSixteenLettersDigitsOrDashes() {
    #expect(QALaunch.isValidName("A"))
    #expect(QALaunch.isValidName("a-b-9"))
    #expect(!QALaunch.isValidName(""))
    #expect(!QALaunch.isValidName("12345678901234567"))
    #expect(!QALaunch.isValidName("../Vortex"))
    #expect(!QALaunch.isValidName("a/b"))
    #expect(!QALaunch.isValidName("a b"))
    #expect(!QALaunch.isValidName("tester_1"))
    #expect(!QALaunch.isValidName("é"))
    #expect(!QALaunch.isValidName("ａ"))
  }

  @Test
  func aBadQAArgumentStopsTheAppInsteadOfStartingPlainVortex() {
    #expect(isInvalid(launch("--qa")))
    #expect(isInvalid(launch("--qa", "")))
    #expect(isInvalid(launch("--qa", "../../Vortex")))
    #expect(isInvalid(launch("--qa", "A", "--qa", "B")))
    #expect(isInvalid(launch("--qa=A")))
    #expect(isInvalid(launch("--QA", "A")))
    #expect(isInvalid(launch("--qaa", "A")))
    // The next QA option means the name is missing.
    #expect(isInvalid(launch("--qa", "--qa-release")))
  }

  @Test
  func optionsComeWithAName() {
    #expect(
      launch("--qa", "A", "--qa-reduce-motion", "--qa-release", "--qa-screens", "notch+plain")
        == .named("a", .init(reduceMotion: true, releaseBehavior: true, screens: [.notch, .plain]))
    )
    #expect(launch("--qa-release", "--qa", "A").options == .init(releaseBehavior: true))
    #expect(launch("--qa", "A").options == .init())
    #expect(launch().options == nil)
  }

  @Test
  func badOptionsStopTheApp() {
    #expect(isInvalid(launch("--qa-release")))
    #expect(isInvalid(launch("--qa", "A", "--qa-relese")))
    #expect(isInvalid(launch("--qa", "A", "--qa-screens")))
    #expect(isInvalid(launch("--qa", "A", "--qa-screens", "wide")))
    #expect(isInvalid(launch("--qa", "A", "--qa-release", "--qa-release")))
  }

  @Test
  func screensAreNotchesAndPlainDisplays() {
    #expect(QALaunch.screens("notch") == [.notch])
    #expect(QALaunch.screens("plain") == [.plain])
    #expect(QALaunch.screens("notch+plain") == [.notch, .plain])
    #expect(QALaunch.screens("plain+notch+plain") == [.plain, .notch, .plain])
    #expect(QALaunch.screens("") == nil)
    #expect(QALaunch.screens("notch+") == nil)
    #expect(QALaunch.screens("notch+plain+plain+plain") == nil)
    #expect(QALaunch.screens("Notch") == nil)
  }

  @Test
  func aQARunKeepsItsDataInAFolderOfItsOwn() {
    let base = URL(fileURLWithPath: "/Users/someone/Library/Application Support", isDirectory: true)
    #expect(DataFolder.folder(in: base, qa: .none).path == "/Users/someone/Library/Application Support/Vortex")
    #expect(
      DataFolder.folder(in: base, qa: .named("a", .init())).path
        == "/Users/someone/Library/Application Support/Vortex QA/a"
    )
    #expect(DataFolder.qaRoot(in: base).path == "/Users/someone/Library/Application Support/Vortex QA")
  }

  @Test
  func testsUseTheUsualFolder() {
    #expect(QALaunch.current == .none)
    #expect(DataFolder.url.lastPathComponent == "Vortex")
  }
}
