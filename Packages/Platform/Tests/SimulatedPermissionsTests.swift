#if DEBUG
  import Foundation
  import Testing
  import VortexCore

  @testable import VortexPlatform

  /// The simulated macOS that unit tests and QA mode use: it has to behave as macOS does.
  struct SimulatedPermissionsTests {
    @Test
    func aFreshMacHasNothingGrantedAndNoPasteboardPrivacy() {
      let mac = SimulatedPermissions()
      #expect(mac.statuses == [
        .notifications: .notGranted, .accessibility: .notGranted, .screenRecording: .notGranted, .pasteboard: .notNeeded,
      ])
      #expect(mac.state.events.isEmpty)
    }

    // MARK: Notifications

    @Test
    func notificationsAreGrantedInMacOSsOwnPromptThenOnlyTheirPaneOpens() {
      let mac = SimulatedPermissions()
      mac.answer(.notifications, with: .allow)
      mac.request(.notifications)
      #expect(mac.statuses[.notifications] == .granted)
      #expect(mac.state.events == [.prompt(.notifications)])
      mac.request(.notifications)
      #expect(mac.state.events == [.prompt(.notifications), .settings(.notifications)])
    }

    @Test
    func deniedNotificationsOpenTheirPaneAndAGrantThereIsSeenAtTheNextRead() {
      let mac = SimulatedPermissions()
      mac.answer(.notifications, with: .deny)
      mac.request(.notifications)
      #expect(mac.statuses[.notifications] == .notGranted)
      mac.request(.notifications)
      #expect(mac.state.events == [.prompt(.notifications), .settings(.notifications)])
      // macOS sends no signal for notifications: the app sees the switch when it reads again.
      mac.toggle(.notifications, on: true)
      #expect(mac.statuses[.notifications] == .notGranted)
      mac.refresh()
      #expect(mac.statuses[.notifications] == .granted)
    }

    /// An ignored banner leaves notifications undetermined, and macOS shows its prompt only once.
    @Test
    func anIgnoredNotificationPromptNeverShowsAgain() {
      let mac = SimulatedPermissions()
      mac.request(.notifications)
      mac.request(.notifications)
      #expect(mac.statuses[.notifications] == .notGranted)
      #expect(mac.state.events == [.prompt(.notifications), .settings(.notifications)])
      // Without the app's memory, as after a reinstall, it asks macOS again: nothing shows, so the pane opens.
      mac.forgetRequests()
      mac.request(.notifications)
      #expect(mac.state.events == [.prompt(.notifications), .settings(.notifications), .settings(.notifications)])
      // Allowed later in Notification Center.
      mac.toggle(.notifications, on: true)
      mac.refresh()
      #expect(mac.statuses[.notifications] == .granted)
    }

    // MARK: Accessibility

    @Test
    func aFirstAccessibilityRequestOnlyPromptsWhenTheAlertComesUpThenThePaneOpens() {
      let mac = SimulatedPermissions()
      mac.request(.accessibility)
      #expect(mac.state.events == [.prompt(.accessibility)])
      #expect(mac.statuses[.accessibility] == .notGranted)
      mac.request(.accessibility)
      #expect(mac.state.events == [.prompt(.accessibility), .settings(.accessibility)])
    }

    /// The prompt's «Open System Settings» lists Vortex switched off and opens the pane; the switch grants it at once.
    @Test
    func openSystemSettingsInThePromptListsVortexOffAndTheSwitchGrantsItLive() {
      let mac = SimulatedPermissions()
      mac.answer(.accessibility, with: .allow)
      mac.request(.accessibility)
      #expect(mac.state.settings[.accessibility] == .denied)
      #expect(mac.state.events == [.prompt(.accessibility), .settings(.accessibility)])
      #expect(mac.statuses[.accessibility] == .notGranted)
      mac.toggle(.accessibility, on: true)
      #expect(mac.statuses[.accessibility] == .granted)
      mac.toggle(.accessibility, on: false)
      #expect(mac.statuses[.accessibility] == .notGranted)
    }

    /// Listed already but never asked in Vortex's memory, as after an upgrade or a reinstall: macOS shows nothing, so
    /// the pane opens and the first click is never dead.
    @Test
    func aListedAppsFirstRequestOpensThePane() {
      for permission in [Permission.accessibility, .screenRecording] {
        let mac = SimulatedPermissions()
        mac.set(permission, to: .denied)
        mac.request(permission)
        #expect(mac.state.events == [.settings(permission)])
      }
    }

    /// Removed from the list with "−" after Vortex asked: the pane, without macOS's prompt.
    @Test
    func onceAskedTheAccessibilityPaneOpensDirectly() {
      let mac = SimulatedPermissions()
      mac.answer(.accessibility, with: .deny)
      mac.request(.accessibility)
      mac.set(.accessibility, to: .notAsked)
      mac.request(.accessibility)
      #expect(mac.state.events == [.prompt(.accessibility), .settings(.accessibility)])
    }

    // MARK: Screen Recording

    @Test
    func screenRecordingGrantedDuringTheSessionWorksAfterARelaunch() {
      let mac = SimulatedPermissions()
      mac.answer(.screenRecording, with: .allow)
      mac.request(.screenRecording)
      #expect(mac.state.events == [.prompt(.screenRecording), .settings(.screenRecording)])
      mac.toggle(.screenRecording, on: true)
      #expect(mac.statuses[.screenRecording] == .grantedAfterRestart)
      mac.relaunch()
      #expect(mac.statuses[.screenRecording] == .granted)
      #expect(mac.state.events.last == .relaunch)
    }

    @Test
    func aLiveScreenRecordingGrantWorksAtOnce() {
      let mac = SimulatedPermissions()
      mac.setLiveScreenRecording(true)
      mac.request(.screenRecording)
      mac.toggle(.screenRecording, on: true)
      #expect(mac.statuses[.screenRecording] == .granted)
    }

    /// Without a request of Vortex's own the probe never runs: the grant counts after a relaunch, or a request.
    @Test
    func screenRecordingTurnedOnWithoutARequestCountsAfterARelaunchOrARequest() {
      let mac = SimulatedPermissions()
      mac.set(.screenRecording, to: .denied)
      mac.toggle(.screenRecording, on: true)
      #expect(mac.statuses[.screenRecording] == .notGranted)
      mac.request(.screenRecording)
      #expect(mac.statuses[.screenRecording] == .grantedAfterRestart)

      let relaunched = SimulatedPermissions()
      relaunched.toggle(.screenRecording, on: true)
      relaunched.relaunch()
      #expect(relaunched.statuses[.screenRecording] == .granted)
    }

    @Test
    func screenRecordingTurnedOffIsNotGrantedAtOnce() {
      let duringSession = SimulatedPermissions()
      duringSession.request(.screenRecording)
      duringSession.toggle(.screenRecording, on: true)
      duringSession.toggle(.screenRecording, on: false)
      #expect(duringSession.statuses[.screenRecording] == .notGranted)

      let sinceLaunch = SimulatedPermissions()
      sinceLaunch.set(.screenRecording, to: .granted)
      #expect(sinceLaunch.statuses[.screenRecording] == .granted)
      sinceLaunch.toggle(.screenRecording, on: false)
      #expect(sinceLaunch.statuses[.screenRecording] == .notGranted)
    }

    @Test
    func laterScreenRecordingRequestsOnlyOpenThePane() {
      let mac = SimulatedPermissions()
      mac.request(.screenRecording)
      mac.request(.screenRecording)
      #expect(mac.state.events == [.prompt(.screenRecording), .settings(.screenRecording)])
    }

    // MARK: Pasteboard

    @Test
    func withoutPasteboardPrivacyThePasteboardIsNeverNeeded() {
      let mac = SimulatedPermissions()
      for setting in SimulatedPermissions.Setting.allCases {
        mac.set(.pasteboard, to: setting)
        #expect(mac.statuses[.pasteboard] == .notNeeded)
      }
    }

    @Test
    func aPasteboardGrantCountsOnlyAfterARelaunchAndItHasNoPrompt() {
      let mac = SimulatedPermissions()
      mac.setPasteboardAsks(true)
      #expect(mac.statuses[.pasteboard] == .notNeeded)
      mac.set(.pasteboard, to: .denied)
      #expect(mac.statuses[.pasteboard] == .notGranted)
      mac.answer(.pasteboard, with: .allow)
      mac.request(.pasteboard)
      #expect(mac.state.events == [.settings(.pasteboard)])
      #expect(mac.state.requested.isEmpty)
      mac.toggle(.pasteboard, on: true)
      #expect(mac.statuses[.pasteboard] == .notGranted)
      mac.relaunch()
      #expect(mac.statuses[.pasteboard] == .notNeeded)
    }

    // MARK: Reads, frequent checks, saving

    @Test
    func updatesGiveTheStatusesNowThenOnlyChanges() async {
      let mac = SimulatedPermissions()
      var updates = mac.updates().makeAsyncIterator()
      #expect(await updates.next()?[.accessibility] == .notGranted)
      // Opening a pane changes no status.
      mac.openSettings(.accessibility)
      mac.toggle(.accessibility, on: true)
      #expect(await updates.next()?[.accessibility] == .granted)
      mac.toggle(.accessibility, on: true)
      mac.toggle(.accessibility, on: false)
      #expect(await updates.next()?[.accessibility] == .notGranted)
    }

    @Test
    func aNotificationsChangeReachesListenersAtTheNextReadOrAtOnceDuringFrequentChecks() async {
      let mac = SimulatedPermissions()
      var updates = mac.updates().makeAsyncIterator()
      _ = await updates.next()
      mac.toggle(.notifications, on: true)
      mac.refresh()
      #expect(await updates.next()?[.notifications] == .granted)
      mac.setFrequentChecks(true)
      mac.toggle(.notifications, on: false)
      #expect(await updates.next()?[.notifications] == .notGranted)
    }

    @Test
    func frequentChecksAreKeptUntilARelaunch() {
      let mac = SimulatedPermissions()
      mac.setFrequentChecks(true)
      #expect(mac.state.frequentChecks)
      mac.relaunch()
      #expect(!mac.state.frequentChecks)
    }

    @Test
    func theStateSurvivesARelaunchOfTheApp() throws {
      let mac = SimulatedPermissions()
      mac.answer(.screenRecording, with: .allow)
      mac.request(.screenRecording)
      mac.toggle(.screenRecording, on: true)
      mac.setPasteboardAsks(true)
      #expect(mac.statuses[.screenRecording] == .grantedAfterRestart)

      let saved = try JSONEncoder().encode(mac.state)
      let restored = SimulatedPermissions(try JSONDecoder().decode(SimulatedPermissions.State.self, from: saved))
      #expect(restored.state == mac.state)
      restored.relaunch()
      #expect(restored.statuses[.screenRecording] == .granted)
      // Requested before the relaunch: the pane, no prompt.
      restored.request(.screenRecording)
      #expect(restored.state.events.suffix(2) == [.relaunch, .settings(.screenRecording)])
    }

    @Test
    func theClientDrivesTheSimulatedMac() async {
      let mac = SimulatedPermissions()
      let client = PermissionsClient.simulated(mac)
      mac.answer(.notifications, with: .allow)
      await client.request(.notifications)
      #expect(await client.statuses()[.notifications] == .granted)
      await client.openSettings(.screenRecording)
      await client.setFrequentChecks(true)
      #expect(mac.state.events == [.prompt(.notifications), .settings(.screenRecording)])
      #expect(mac.state.frequentChecks)
      mac.setFrequentChecks(false)
      mac.toggle(.notifications, on: false)
      #expect(mac.statuses[.notifications] == .granted)
      await client.refresh()
      #expect(mac.statuses[.notifications] == .notGranted)
      // `statuses()` reads too.
      mac.toggle(.notifications, on: true)
      #expect(await client.statuses()[.notifications] == .granted)
      var updates = client.updates().makeAsyncIterator()
      #expect(await updates.next() == mac.statuses)
    }
  }
#endif
