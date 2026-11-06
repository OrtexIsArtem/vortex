#if DEBUG
  import ComposableArchitecture
  import Foundation
  import UserNotifications
  import VortexCore

  /// macOS's permissions, simulated for unit tests and QA mode: what System Settings holds, what the app saw at launch,
  /// macOS's prompts and the user's answers. Statuses come out of the same rules as the live client's
  /// (`PermissionRules.swift`), and requests take the same steps, so the two behave alike:
  /// - macOS shows its prompt only while the app isn't listed, and once: an unanswered notification prompt leaves
  ///   notifications undetermined, and asking again shows nothing;
  /// - the answer to a prompt is scripted: allow, deny or ignore;
  /// - the user can flip the switch in System Settings (`toggle`);
  /// - Screen Recording and the pasteboard count as they were at launch until `relaunch()`; with `liveScreenRecording`
  ///   a Screen Recording grant works at once;
  /// - the app sees a change when it reads: at once for the privacy permissions, whose change macOS signals; for
  ///   notifications, which have none, only on `refresh()` (an app becoming active, the notch window opening) or while
  ///   frequent checks are on;
  /// - `events` logs the prompts shown and the panes opened;
  /// - `state` is Codable: save it, and to go on after the app relaunched, pass it to `init` and call `relaunch()`.
  public final class SimulatedPermissions: Sendable {
    /// What System Settings holds for a permission: the app not listed (for notifications: never answered), listed
    /// but off, on.
    public enum Setting: String, Codable, CaseIterable, Sendable {
      case notAsked, denied, granted
    }

    /// The user's answer to macOS's prompt. The prompt for Accessibility and Screen Recording only lists the app and
    /// offers System Settings, so there `allow` is «Open System Settings»: the app is listed off and the pane opens.
    /// `ignore` leaves the prompt unanswered: a notification banner slides away, an alert stays up.
    public enum Answer: String, Codable, CaseIterable, Sendable {
      case allow, deny, ignore
    }

    public enum Event: Equatable, Codable, Sendable {
      /// macOS showed its prompt.
      case prompt(Permission)
      /// System Settings opened at the permission's pane.
      case settings(Permission)
      /// The app relaunched.
      case relaunch
    }

    public struct State: Equatable, Codable, Sendable {
      /// What System Settings holds now; a permission left out is `notAsked`.
      public var settings: [Permission: Setting] = [:]
      /// What System Settings held when the app started.
      public var settingsAtLaunch: [Permission: Setting] = [:]
      /// The answer to every prompt of a permission from now on; a permission left out is `ignore`.
      public var answers: [Permission: Answer] = [:]
      /// macOS has shown its prompt while the permission is `notAsked`, and won't show it again until it is answered
      /// or reset.
      public var prompted: Set<Permission> = []
      /// The permissions the app has requested: its own memory, DataFolder/permissions.json in the live client.
      public var requested: Set<Permission> = []
      /// macOS lets a Screen Recording grant work without a relaunch, as AltTab measured on macOS 27.
      public var liveScreenRecording = false
      /// macOS enforces pasteboard privacy. macOS 26.4 doesn't, and the pasteboard is then `notNeeded`.
      public var pasteboardAsks = false
      /// The 1 s re-read is on.
      public var frequentChecks = false
      /// Prompts shown and panes opened, oldest first.
      public var events: [Event] = []

      public init() {}
    }

    private struct Model {
      var state: State
      var screenRecording: ScreenRecordingDetector
      /// What the app read last.
      var statuses: [Permission: PermissionStatus] = [:]
      var listeners: [UUID: AsyncStream<[Permission: PermissionStatus]>.Continuation] = [:]
    }

    private let model: LockIsolated<Model>

    /// The app started with this state.
    public init(_ state: State = State()) {
      var model = Model(
        state: state,
        screenRecording: ScreenRecordingDetector(grantedAtLaunch: state.settingsAtLaunch[.screenRecording] == .granted)
      )
      model.statuses = Self.read(model.state, &model.screenRecording)
      let started = model
      self.model = LockIsolated(started)
    }

    public var state: State { model.value.state }

    /// What the app read last.
    public var statuses: [Permission: PermissionStatus] { model.value.statuses }

    /// The statuses now and on every change.
    public func updates() -> AsyncStream<[Permission: PermissionStatus]> {
      let (stream, continuation) = AsyncStream.makeStream(of: [Permission: PermissionStatus].self)
      let id = UUID()
      continuation.onTermination = { [model] _ in
        model.withValue { _ = $0.listeners.removeValue(forKey: id) }
      }
      model.withValue { model in
        continuation.yield(model.statuses)
        model.listeners[id] = continuation
      }
      return stream
    }

    // MARK: The world

    /// Sets what System Settings holds as if it had been so since the app started, with no prompt shown.
    public func set(_ permission: Permission, to setting: Setting) {
      change { model in
        model.state.settings[permission] = setting
        model.state.settingsAtLaunch[permission] = setting
        model.state.prompted.remove(permission)
        if permission == .screenRecording {
          model.screenRecording = ScreenRecordingDetector(grantedAtLaunch: setting == .granted)
        }
      }
    }

    /// The user flips the app's switch in System Settings now, which lists the app if it wasn't. macOS signals the
    /// change of a privacy permission; one of notifications the app sees at its next read.
    public func toggle(_ permission: Permission, on isOn: Bool) {
      change(reads: { $0.frequentChecks || permission != .notifications }) { model in
        model.state.settings[permission] = isOn ? .granted : .denied
        model.state.prompted.remove(permission)
      }
    }

    /// How the user answers every prompt of the permission from now on.
    public func answer(_ permission: Permission, with answer: Answer) {
      change { $0.state.answers[permission] = answer }
    }

    public func setLiveScreenRecording(_ isOn: Bool) {
      change { $0.state.liveScreenRecording = isOn }
    }

    /// Whether macOS enforces pasteboard privacy, as if it had since the app started.
    public func setPasteboardAsks(_ isOn: Bool) {
      change { $0.state.pasteboardAsks = isOn }
    }

    /// The app's own memory of its requests is gone, as after a reinstall or with a new data folder; macOS keeps its
    /// lists.
    public func forgetRequests() {
      change { $0.state.requested = [] }
    }

    /// The app quits and starts again: it now sees what System Settings holds.
    public func relaunch() {
      change { model in
        model.state.settingsAtLaunch = model.state.settings
        model.state.frequentChecks = false
        model.state.events.append(.relaunch)
        model.screenRecording = ScreenRecordingDetector(grantedAtLaunch: model.state.settings[.screenRecording] == .granted)
      }
    }

    // MARK: The client

    /// The app reads again, as the live client does on macOS's signal, when an app becomes active, when the notch
    /// window opens, and once a second during frequent checks.
    public func refresh() {
      change { _ in }
    }

    public func setFrequentChecks(_ isOn: Bool) {
      change { $0.state.frequentChecks = isOn }
    }

    /// As the live client: the same steps, and a read after them.
    public func request(_ permission: Permission) {
      change { model in
        let askedBefore = model.state.requested.contains(permission)
        if permission.remembersRequests { model.state.requested.insert(permission) }
        let notificationsDetermined = (model.state.settings[.notifications] ?? .notAsked) != .notAsked
        for step in permission.requestSteps(askedBefore: askedBefore, notificationsDetermined: notificationsDetermined) {
          switch step {
          case .promptOrSettings:
            // macOS's prompt comes up, or the app opens the pane: an alert or System Settings within 1.5 s, or a
            // notifications request that doesn't come back at once with no answer.
            if !Self.prompt(permission, &model.state) { model.state.events.append(.settings(permission)) }
          case .openSettings:
            model.state.events.append(.settings(permission))
          }
        }
      }
    }

    public func openSettings(_ permission: Permission) {
      change { $0.state.events.append(.settings(permission)) }
    }

    // MARK: macOS

    /// macOS's prompt: shown only while the app isn't listed and only once, then the scripted answer. Returns whether
    /// it showed.
    @discardableResult
    private static func prompt(_ permission: Permission, _ state: inout State) -> Bool {
      guard permission != .pasteboard, (state.settings[permission] ?? .notAsked) == .notAsked,
            !state.prompted.contains(permission)
      else { return false }
      state.events.append(.prompt(permission))
      switch state.answers[permission] ?? .ignore {
      case .ignore:
        state.prompted.insert(permission)
      case .deny:
        state.settings[permission] = .denied
      case .allow where permission == .notifications:
        state.settings[permission] = .granted
      case .allow:
        state.settings[permission] = .denied
        state.events.append(.settings(permission))
      }
      return true
    }

    /// What the app reads, by the live client's rules.
    private static func read(_ state: State, _ screenRecording: inout ScreenRecordingDetector) -> [Permission: PermissionStatus] {
      func now(_ permission: Permission) -> Setting { state.settings[permission] ?? .notAsked }
      func atLaunch(_ permission: Permission) -> Setting { state.settingsAtLaunch[permission] ?? .notAsked }

      let notifications: UNAuthorizationStatus = switch now(.notifications) {
      case .notAsked: .notDetermined
      case .denied: .denied
      case .granted: .authorized
      }
      // macOS shows other apps' titles as soon as the switch is on; capture works if it was on at launch.
      let titles: WindowTitles = now(.screenRecording) == .granted ? .visible : .hidden
      let asked = state.requested.contains(.screenRecording)
      let captureWorks = atLaunch(.screenRecording) == .granted
        || (state.liveScreenRecording && now(.screenRecording) == .granted)
      screenRecording.update(
        titles,
        asked: asked,
        probeSucceeded: screenRecording.needsProbe(titles, asked: asked) && captureWorks
      )
      // Without enforcement macOS 26.4 reports `.alwaysAllow`; with it, an app never asked reports `.default`.
      let pasteboard: PasteboardAccess = if !state.pasteboardAsks {
        .alwaysAllow
      } else {
        switch atLaunch(.pasteboard) {
        case .notAsked: .default
        case .denied: .ask
        case .granted: .alwaysAllow
        }
      }
      return [
        .notifications: PermissionStatus(notifications: notifications),
        .accessibility: now(.accessibility) == .granted ? .granted : .notGranted,
        .screenRecording: screenRecording.status,
        .pasteboard: PermissionStatus(pasteboard: pasteboard),
      ]
    }

    /// Changes the model and, when the app would read now, reads and tells the listeners of a change.
    private func change(reads: @Sendable (State) -> Bool = { _ in true }, _ body: @Sendable (inout Model) -> Void) {
      model.withValue { model in
        body(&model)
        guard reads(model.state) else { return }
        let statuses = Self.read(model.state, &model.screenRecording)
        guard statuses != model.statuses else { return }
        model.statuses = statuses
        for listener in model.listeners.values {
          listener.yield(statuses)
        }
      }
    }
  }

  extension PermissionsClient {
    /// A client over simulated permissions, for unit tests and QA mode.
    public static func simulated(_ permissions: SimulatedPermissions) -> PermissionsClient {
      PermissionsClient(
        statuses: {
          permissions.refresh()
          return permissions.statuses
        },
        updates: { permissions.updates() },
        setFrequentChecks: { isOn in permissions.setFrequentChecks(isOn) },
        request: { permission in permissions.request(permission) },
        openSettings: { permission in permissions.openSettings(permission) },
        refresh: { permissions.refresh() },
        requested: { permissions.state.requested }
      )
    }
  }
#endif
