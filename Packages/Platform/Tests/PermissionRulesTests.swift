import ComposableArchitecture
import Foundation
import Testing
import UserNotifications
import VortexCore

@testable import VortexPlatform

/// The rules behind the live client's statuses and requests. Nothing here asks macOS: the system's answers are inputs.
struct PermissionRulesTests {
  // MARK: Reading

  @Test
  func notificationsAllowedEvenQuietlyAreGranted() {
    #expect(PermissionStatus(notifications: .authorized) == .granted)
    #expect(PermissionStatus(notifications: .provisional) == .granted)
    #expect(PermissionStatus(notifications: .notDetermined) == .notGranted)
    #expect(PermissionStatus(notifications: .denied) == .notGranted)
  }

  /// macOS 26.4 reports `.alwaysAllow` for an app while it doesn't enforce pasteboard privacy, and `.default` for one it
  /// never asked: the pasteboard then shows nowhere. Only an app macOS asks, or denies, has something to do.
  @Test
  func thePasteboardNeedsSomethingOnlyWhenMacOSAsksOrDenies() {
    #expect(PermissionStatus(pasteboard: .ask) == .notGranted)
    #expect(PermissionStatus(pasteboard: .alwaysDeny) == .notGranted)
    #expect(PermissionStatus(pasteboard: .alwaysAllow) == .notNeeded)
    #expect(PermissionStatus(pasteboard: .default) == .notNeeded)
    // Before macOS 15.4 there is no pasteboard privacy.
    #expect(PermissionStatus(pasteboard: nil) == .notNeeded)
  }

  // MARK: Requests

  @Test
  func notificationsPromptOnlyTheFirstTimeAndOnlyIfMacOSNeverHadAnAnswer() {
    #expect(Permission.notifications.requestSteps(askedBefore: false, notificationsDetermined: false) == [.promptOrSettings])
    // Answered before Vortex remembers asking, as by an older Vortex: the pane.
    #expect(Permission.notifications.requestSteps(askedBefore: false, notificationsDetermined: true) == [.openSettings])
  }

  /// An unanswered prompt keeps notifications undetermined, and asking again would show nothing.
  @Test
  func onceAskedNotificationsOpenTheirPaneWhateverTheStatus() {
    #expect(Permission.notifications.requestSteps(askedBefore: true, notificationsDetermined: false) == [.openSettings])
    #expect(Permission.notifications.requestSteps(askedBefore: true, notificationsDetermined: true) == [.openSettings])
  }

  /// The first request: macOS's prompt, and the pane only if nothing came up, never both at once.
  @Test
  func aFirstRequestPromptsAndOpensThePaneOnlyIfNothingComesUp() {
    for permission in [Permission.accessibility, .screenRecording] {
      #expect(permission.requestSteps(askedBefore: false, notificationsDetermined: true) == [.promptOrSettings])
    }
  }

  @Test
  func laterRequestsOpenThePaneDirectly() {
    for permission in [Permission.accessibility, .screenRecording] {
      #expect(permission.requestSteps(askedBefore: true, notificationsDetermined: true) == [.openSettings])
    }
  }

  @Test
  func thePasteboardHasNoPromptOnlyItsPaneAndNothingToRemember() {
    #expect(Permission.pasteboard.requestSteps(askedBefore: false, notificationsDetermined: true) == [.openSettings])
    #expect(Permission.pasteboard.requestSteps(askedBefore: true, notificationsDetermined: true) == [.openSettings])
    #expect(Permission.allCases.filter(\.remembersRequests) == [.notifications, .accessibility, .screenRecording])
  }

  /// macOS's alert app on macOS 26.4, read from its Info.plist, and System Settings.
  @Test
  func macOSsAlertOrSystemSettingsCountAsSomethingComingUp() async {
    #expect(PromptWatch.alertApp == "com.apple.accessibility.universalAccessAuthWarn")
    #expect(PromptWatch.promptApps == [PromptWatch.alertApp, "com.apple.systempreferences"])
    for app in PromptWatch.promptApps {
      let (apps, continuation) = AsyncStream.makeStream(of: String.self)
      continuation.yield("com.apple.finder")
      continuation.yield(app)
      let askedForTheAlert = LockIsolated(false)
      #expect(await PromptWatch.comesUp(apps, within: .seconds(30)) {
        askedForTheAlert.setValue(true)
        return false
      })
      #expect(!askedForTheAlert.value)
    }
  }

  /// The alert app may be running already, from a request a moment before, or show its alert without becoming
  /// active: its window on screen at the end counts too.
  @Test
  func withNothingLaunchedOrActivatedTheAlertsWindowDecides() async {
    let (apps, continuation) = AsyncStream.makeStream(of: String.self)
    continuation.yield("com.apple.finder")
    #expect(await PromptWatch.comesUp(apps, within: .milliseconds(50)) { true })
    #expect(await !PromptWatch.comesUp(AsyncStream { $0.finish() }, within: .milliseconds(50)) { false })
    continuation.finish()
  }

  @Test
  func theAlertIsUpWhileAWindowOfTheAlertAppIsOnScreen() {
    let alert: pid_t = 700
    let windows = [
      ListedWindow(ownerPID: 200, layer: 0, name: nil, ownerIsRegularApp: true),
      ListedWindow(ownerPID: alert, layer: 8, name: nil, ownerIsRegularApp: false),
    ]
    #expect(PromptWatch.alertIsUp(windows, alertApps: [alert]))
    #expect(!PromptWatch.alertIsUp(Array(windows.prefix(1)), alertApps: [alert]))
    // The alert app isn't running.
    #expect(!PromptWatch.alertIsUp(windows, alertApps: []))
  }

  /// `requestAuthorization` waits for the answer while its prompt shows; back at once with no answer, macOS showed
  /// nothing and the pane opens.
  @Test
  func notificationsShowedNothingWhenTheRequestCameBackAtOnceWithNoAnswer() {
    #expect(PromptWatch.notificationsShowedNothing(returnedQuickly: true, authorization: .notDetermined))
    // Answered at once, either way: the prompt showed.
    #expect(!PromptWatch.notificationsShowedNothing(returnedQuickly: true, authorization: .authorized))
    #expect(!PromptWatch.notificationsShowedNothing(returnedQuickly: true, authorization: .denied))
    // Still waiting: the prompt is up.
    #expect(!PromptWatch.notificationsShowedNothing(returnedQuickly: false, authorization: .notDetermined))
  }

  @Test
  func workGetsAResultOnlyWithinItsLimit() async {
    #expect(await Deadline.result(within: .seconds(30)) { 7 } == 7)
    let slow = await Deadline.result(within: .milliseconds(50)) { () -> Int in
      try? await Task.sleep(for: .seconds(2))
      return 7
    }
    #expect(slow == nil)
  }

  @Test
  func eachPermissionOpensItsOwnPane() {
    let id = "io.github.ortexisartem.vortex"
    #expect(
      Permission.notifications.settingsURL(bundleID: id).absoluteString
        == "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=io.github.ortexisartem.vortex"
    )
    #expect(
      Permission.accessibility.settingsURL(bundleID: id).absoluteString
        == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )
    #expect(
      Permission.screenRecording.settingsURL(bundleID: id).absoluteString
        == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )
    #expect(
      Permission.pasteboard.settingsURL(bundleID: id).absoluteString
        == "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard"
    )
  }

  // MARK: What Vortex asked for

  func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: "asked-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  @Test
  func requestsAreRememberedEachOnceInAFileOfTheDataFolder() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    // The folder may not exist yet, as on a first launch.
    let asked = AskedPermissions(url: folder.appending(path: "Vortex/permissions.json"))
    #expect(!asked.contains(.accessibility))
    asked.insert(.accessibility)
    asked.insert(.accessibility)
    asked.insert(.screenRecording)
    #expect(asked.contains(.accessibility))
    #expect(asked.contains(.screenRecording))
    #expect(!asked.contains(.notifications))
    #expect(asked.all == [.accessibility, .screenRecording])
    let file = try String(contentsOf: asked.url, encoding: .utf8)
    #expect(file == #"{"asked":["accessibility","screenRecording"]}"#)
  }

  @Test
  func anUnreadableFileMeansNothingWasAskedAndNamesFromANewerVortexStay() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let asked = AskedPermissions(url: folder.appending(path: "permissions.json"))
    try Data("not json".utf8).write(to: asked.url)
    #expect(!asked.contains(.notifications))
    #expect(asked.all.isEmpty)
    try Data(#"{"asked":["camera"]}"#.utf8).write(to: asked.url)
    asked.insert(.notifications)
    #expect(asked.contains(.notifications))
    // A name this build doesn't know isn't one of its permissions.
    #expect(asked.all == [.notifications])
    #expect(try String(contentsOf: asked.url, encoding: .utf8) == #"{"asked":["camera","notifications"]}"#)
  }

  @Test
  func theFileIsInTheDataFolder() {
    #expect(AskedPermissions.inDataFolder.url == DataFolder.url.appending(path: "permissions.json"))
  }
}

/// Screen Recording after launch: other apps' window titles show a grant, one probe tells now from after a relaunch.
struct ScreenRecordingDetectionTests {
  let me: pid_t = 100
  let finder: pid_t = 200
  let dock: pid_t = 300

  func window(_ pid: pid_t, layer: Int = 0, name: String?, regular: Bool = true) -> ListedWindow {
    ListedWindow(ownerPID: pid, layer: layer, name: name, ownerIsRegularApp: regular)
  }

  // MARK: What the windows show

  @Test
  func anotherAppsTitleMeansTitlesAreVisible() {
    let windows = [window(finder, name: ""), window(finder, name: "Downloads")]
    #expect(WindowTitles(windows, ownPID: me) == .visible)
  }

  @Test
  func otherAppsWindowsWithoutAnyTitleMeanTitlesAreHidden() {
    #expect(WindowTitles([window(finder, name: nil), window(finder, name: nil)], ownPID: me) == .hidden)
  }

  @Test
  func vortexsOwnTitlesShowNothing() {
    #expect(WindowTitles([window(me, name: "Vortex"), window(finder, name: nil)], ownPID: me) == .hidden)
    #expect(WindowTitles([window(me, name: "Vortex")], ownPID: me) == .unknown)
  }

  /// The Dock's, the menu bar's and other system windows keep their titles without the permission.
  @Test
  func systemWindowsAndAgentsShowNothing() {
    let windows = [
      window(dock, layer: 20, name: "Dock"),
      window(dock, layer: 0, name: "Dock", regular: false),
      window(finder, layer: 25, name: "Item-0"),
      window(finder, name: nil),
    ]
    #expect(WindowTitles(windows, ownPID: me) == .hidden)
  }

  @Test
  func untitledWindowsOrNoneTellNothing() {
    // With the permission an untitled window reports an empty title; it may be all there is on screen.
    #expect(WindowTitles([window(finder, name: ""), window(finder, name: nil)], ownPID: me) == .unknown)
    #expect(WindowTitles([], ownPID: me) == .unknown)
  }

  // MARK: The status

  @Test
  func grantedAtLaunchIsGrantedWithoutAProbe() {
    var detector = ScreenRecordingDetector(grantedAtLaunch: true)
    #expect(detector.status == .granted)
    #expect(!detector.needsProbe(.visible, asked: true))
    detector.update(.visible, asked: true)
    #expect(detector.status == .granted)
  }

  @Test
  func titlesAppearingAfterARequestAskForOneProbeThatTellsNowFromAfterARelaunch() {
    var working = ScreenRecordingDetector(grantedAtLaunch: false)
    #expect(working.status == .notGranted)
    #expect(!working.needsProbe(.hidden, asked: true))
    #expect(!working.needsProbe(.unknown, asked: true))
    #expect(working.needsProbe(.visible, asked: true))
    working.update(.visible, asked: true, probeSucceeded: true)
    #expect(working.status == .granted)
    #expect(!working.needsProbe(.visible, asked: true))

    var waiting = ScreenRecordingDetector(grantedAtLaunch: false)
    waiting.update(.visible, asked: true, probeSucceeded: false)
    #expect(waiting.status == .grantedAfterRestart)
    // Confirmed once: later reads don't probe again.
    #expect(!waiting.needsProbe(.visible, asked: true))
    waiting.update(.visible, asked: true)
    #expect(waiting.status == .grantedAfterRestart)
  }

  /// The probe prompts if Vortex isn't listed, so titles alone never start it: only a request of Vortex's own.
  @Test
  func titlesAloneNeitherProbeNorTurnTheStatusOn() {
    var detector = ScreenRecordingDetector(grantedAtLaunch: false)
    #expect(!detector.needsProbe(.visible, asked: false))
    detector.update(.visible, asked: false)
    #expect(detector.status == .notGranted)
    // Requested later: the next read confirms it.
    #expect(detector.needsProbe(.visible, asked: true))
    detector.update(.visible, asked: true, probeSucceeded: true)
    #expect(detector.status == .granted)
  }

  @Test
  func titlesDisappearingAfterAGrantMeanItWasTurnedOff() {
    var detector = ScreenRecordingDetector(grantedAtLaunch: false)
    detector.update(.visible, asked: true, probeSucceeded: false)
    detector.update(.unknown, asked: true)
    #expect(detector.status == .grantedAfterRestart)
    detector.update(.hidden, asked: true)
    #expect(detector.status == .notGranted)
    // Turned on again: a new probe.
    #expect(detector.needsProbe(.visible, asked: true))
    detector.update(.visible, asked: true, probeSucceeded: true)
    #expect(detector.status == .granted)

    var fromLaunch = ScreenRecordingDetector(grantedAtLaunch: true)
    fromLaunch.update(.visible, asked: false)
    fromLaunch.update(.hidden, asked: false)
    #expect(fromLaunch.status == .notGranted)
  }

  /// At login other apps may have no titled window yet: hidden titles then say nothing about a grant from launch.
  @Test
  func aGrantFromLaunchStaysUntilItsTitlesHaveBeenSeen() {
    var detector = ScreenRecordingDetector(grantedAtLaunch: true)
    detector.update(.hidden, asked: false)
    #expect(detector.status == .granted)
  }

  @Test
  func nothingToTellByKeepsTheStatus() {
    var off = ScreenRecordingDetector(grantedAtLaunch: false)
    off.update(.unknown, asked: true)
    off.update(.hidden, asked: true)
    #expect(off.status == .notGranted)
  }
}
