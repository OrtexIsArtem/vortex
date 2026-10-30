#if DEBUG
  import Foundation
  import Testing
  import VortexCore

  @testable import VortexPlatform

  /// The `perm` command on the simulated macOS of a QA run, and presses on a feature's permission row.
  @MainActor
  struct QAPermissionsTests {
    @Test
    func permSetsAnswersTogglesAndFlagsAsMacOSWould() throws {
      let simulated = SimulatedPermissions()
      try QAPermissions.apply(["set": "accessibility:granted,notifications:denied"], to: simulated)
      #expect(simulated.statuses[.accessibility] == .granted)
      #expect(simulated.statuses[.notifications] == .notGranted)
      try QAPermissions.apply(["answer": "screenRecording:allow", "toggle": "accessibility:off"], to: simulated)
      #expect(simulated.state.answers[.screenRecording] == .allow)
      #expect(simulated.statuses[.accessibility] == .notGranted)
      try QAPermissions.apply(["pasteboardAsks": "true", "liveScreenRecording": "true"], to: simulated)
      #expect(simulated.state.pasteboardAsks)
      #expect(simulated.state.liveScreenRecording)
      // Only `perm`: no prompt, no pane.
      #expect(simulated.state.events.isEmpty)
    }

    @Test
    func aBadArgumentChangesNothing() {
      let simulated = SimulatedPermissions()
      #expect(throws: QAError.self) { try QAPermissions.apply(["set": "accessibility:granted,camera:granted"], to: simulated) }
      #expect(throws: QAError.self) { try QAPermissions.apply(["set": "accessibility:on"], to: simulated) }
      #expect(throws: QAError.self) { try QAPermissions.apply(["answer": "accessibility:maybe"], to: simulated) }
      #expect(throws: QAError.self) { try QAPermissions.apply(["toggle": "accessibility:yes"], to: simulated) }
      #expect(throws: QAError.self) { try QAPermissions.apply(["pasteboardAsks": "1"], to: simulated) }
      #expect(throws: QAError.self) { try QAPermissions.apply(["set": "accessibility:granted", "volume": "11"], to: simulated) }
      #expect(simulated.state.settings.isEmpty)
    }

    /// The state is saved and read back as after a relaunch: a grant that waited for one now works.
    @Test
    func aSavedStateStartsAsAfterARelaunch() throws {
      let simulated = SimulatedPermissions()
      simulated.request(.screenRecording)
      simulated.toggle(.screenRecording, on: true)
      #expect(simulated.statuses[.screenRecording] == .grantedAfterRestart)
      let data = try JSONEncoder().encode(simulated.state)
      let restored = SimulatedPermissions(try JSONDecoder().decode(SimulatedPermissions.State.self, from: data))
      restored.relaunch()
      #expect(restored.statuses[.screenRecording] == .granted)
    }

    @Test
    func aRowIsPressedOnlyWhileItShowsThatButton() throws {
      let needs = [PermissionNeed(.notifications, reason: "Tells you when a timer ends.")]
      var opened: [Permission] = []
      var restarts = 0
      func press(_ arguments: [String: String], _ statuses: [Permission: PermissionStatus], showing: Bool = true) throws -> Bool {
        try QAPermissions.pressRow(arguments, needs: needs, statuses: statuses, showing: showing, turnOn: { opened.append($0) }, restart: { restarts += 1 })
      }
      #expect(try press(["press": "turnOn"], [.notifications: .notGranted]))
      #expect(opened == [.notifications])
      #expect(throws: QAError.self) { try press(["press": "turnOn"], [.notifications: .granted]) }
      #expect(throws: QAError.self) { try press(["press": "turnOn"], [:]) }
      #expect(throws: QAError.self) { try press(["press": "restart"], [.notifications: .notGranted]) }
      #expect(try press(["press": "restart"], [.notifications: .grantedAfterRestart]))
      #expect(restarts == 1)
      #expect(throws: QAError.self) { try press(["press": "turnOn", "permission": "accessibility"], [.accessibility: .notGranted]) }
      #expect(try press(["press": "other"], [:]) == false)
      // Settings › Features isn't showing: refused, whatever the row would show.
      #expect(throws: QAError.self) { try press(["press": "turnOn"], [.notifications: .notGranted], showing: false) }
      #expect(opened == [.notifications])
      // Before the shell says what shows, nothing does.
      #expect(!QA.isShowing(.featureSettings))
    }
  }
#endif
