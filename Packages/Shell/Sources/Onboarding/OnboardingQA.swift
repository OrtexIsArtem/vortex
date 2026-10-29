#if DEBUG
  import AppKit
  import ComposableArchitecture
  import VortexCore
  import VortexPlatform

  /// The onboarding's part of QA mode: `onboarding press=…`, `onboarding open`, `onboarding reset`, and the
  /// `onboarding` section of the state dump. Presses do only what the user could: the window must show, and the
  /// button must be there.
  @MainActor
  enum OnboardingQA {
    static func install(store: StoreOf<ShellFeature>) {
      QA.registerState(section: "onboarding") { State(store.onboarding) }
      QA.register(command: "onboarding") { arguments in
        if let press = arguments["press"] {
          try self.press(press, store: store)
        } else if arguments["open"] != nil {
          guard !store.onboarding.progress.completed else {
            throw QAError("the onboarding is completed; `onboarding reset` starts it again")
          }
          store.send(.onboarding(.continueSetupTapped))
        } else if arguments["reset"] != nil {
          store.send(.onboarding(.reset))
        } else {
          throw QAError(
            "onboarding takes press=next|skip|close|escape|start|restart|restartNow|later|back|getStarted|turnOn:<p>|"
              + "row:<p>|pane:<p>|loginItem:on|off|loginItems, open, or reset"
          )
        }
      }
    }

    private static func press(_ button: String, store: StoreOf<ShellFeature>) throws {
      let state = store.onboarding
      guard state.isVisible else { throw QAError("the onboarding window is hidden") }
      let parts = button.split(separator: ":", maxSplits: 1).map(String.init)
      let name = parts[0]
      let permission = parts.count > 1 ? Permission(rawValue: parts[1]) : nil
      func need(_ condition: Bool, _ reason: String) throws {
        guard condition else { throw QAError(reason) }
      }
      let isFlow = state.presentation == .flow && !state.isPanel
      let action: OnboardingFeature.Action
      switch name {
      case "next":
        try need(isFlow && state.buttons.nextVisible, "Next isn't shown")
        action = .nextTapped
      case "skip":
        try need(isFlow && state.buttons.skipVisible, "Skip isn't shown")
        action = .skipTapped
      case "close":
        try need(!state.isPanel, "the panel has no close control")
        action = .closeTapped
      case "escape":
        action = .escapePressed
      case "getStarted":
        try need(isFlow && state.page == .welcome, "Get started is only on Welcome")
        action = .getStartedTapped
      case "start":
        if isFlow, state.page == .welcome {
          action = .getStartedTapped
        } else {
          try need(isFlow && state.page == .done && !state.finishRestarts, "Start using Vortex isn't shown")
          action = .finishTapped
        }
      case "restart":
        if isFlow, state.page == .done {
          try need(state.finishRestarts, "Done's button reads Start using Vortex")
          action = .finishTapped
        } else {
          action = .restartTapped
        }
      case "restartNow":
        try need(isFlow && state.showsRestartNow, "Restart now isn't shown")
        action = .restartTapped
      case "later":
        action = .laterTapped
      case "back":
        try need(state.isPanel, "Back is only on the guide panel")
        action = .backTapped
      case "turnOn":
        guard let permission else { throw QAError("turnOn:<notifications|accessibility|screenRecording|pasteboard>") }
        try need(state.shownPermission == permission || state.guided == permission, "\(permission) has no row here")
        action = .turnOnTapped(permission)
      case "row":
        guard let permission else { throw QAError("row:<permission>") }
        try need(isFlow && state.page == .done && state.rowState(permission) == .off, "\(permission)'s row isn't a button")
        action = .doneRowTapped(permission)
      case "pane":
        guard let permission else { throw QAError("pane:<permission>") }
        try need(state.showsRecheckHint(permission), "the pane button isn't shown")
        action = .openPaneTapped(permission)
      case "loginItem":
        try need(isFlow && state.page == .basics, "Open at login is only on Basics")
        action = .loginItemToggled(parts.count > 1 && parts[1] == "on")
      case "loginItems":
        try need(isFlow && state.page == .basics && state.loginItem == .requiresApproval, "Open Login Items isn't shown")
        action = .openLoginItemsTapped
      default:
        throw QAError("unknown button \(button)")
      }
      store.send(.onboarding(action))
    }

    /// The `onboarding` section of the state dump.
    struct State: Encodable {
      struct Row: Encodable {
        var permission: Permission
        var status: PermissionStatus?
        /// unknown, off, on, afterRestart.
        var checkbox: PermissionRowState
        var required: Bool
        /// "required" while the row shows the Required tag.
        var tag: String?
      }

      struct Frame: Encodable {
        var x, y, width, height: Double
        var visible: Bool
      }

      var page: String
      /// window, guide, single, blocked or hidden.
      var mode: String
      var single: String?
      var singleKind: String?
      var closing: Bool
      var rows: [Row]
      var doneRows: [Row]
      var skipVisible: Bool
      var nextVisible: Bool
      var nextEnabled: Bool
      var navigationLocked: Bool
      /// Done's button: start or restartAndStart; enabled only when nothing required is missing.
      var finish: String
      var finishEnabled: Bool
      var restartNow: Bool
      var notificationHint: Bool
      var recheckHint: [Permission]
      var guided: Permission?
      var guideArmed: Permission?
      var loginItem: String
      var openAtLoginChoice: Bool
      var completed: Bool
      var saved: OnboardingProgress
      var windows: [String: Frame]

      @MainActor init(_ state: OnboardingFeature.State) {
        func row(_ permission: Permission) -> Row {
          let isRequired = state.isRequiredMissing(permission)
          return Row(
            permission: permission,
            status: state.statuses[permission],
            checkbox: state.rowState(permission),
            required: state.catalog.entry(for: permission)?.isRequired == true,
            tag: isRequired ? "required" : nil
          )
        }
        page = state.page.id
        mode = state.mode
        if case let .single(single) = state.presentation {
          self.single = single.permission.rawValue
          singleKind = single.kind.rawValue
          closing = single.isClosing
          rows = [row(single.permission)]
        } else {
          single = nil
          singleKind = nil
          closing = false
          rows = state.rows(on: state.page).map(row)
        }
        doneRows = state.doneRows.map(row)
        let buttons = state.buttons
        skipVisible = buttons.skipVisible
        nextVisible = buttons.nextVisible
        nextEnabled = buttons.nextEnabled
        navigationLocked = state.isNavigationLocked
        finish = state.finishRestarts ? "restartAndStart" : "start"
        finishEnabled = state.finishEnabled
        restartNow = state.showsRestartNow
        notificationHint = state.isNotificationHintVisible
        recheckHint = Permission.allCases.filter(state.showsRecheckHint)
        guided = state.guided
        guideArmed = state.guideArmed
        loginItem = "\(state.loginItem)"
        openAtLoginChoice = state.openAtLoginChoice
        completed = state.progress.completed
        saved = state.progress
        var windows: [String: Frame] = [:]
        let controller = OnboardingWindowController.shared
        for (id, window) in [("onboarding", controller.window as NSWindow?), ("onboarding-panel", controller.panel)] {
          guard let window else { continue }
          let frame = window.frame
          windows[id] = Frame(
            x: frame.minX, y: frame.minY, width: frame.width, height: frame.height, visible: window.isVisible
          )
        }
        self.windows = windows
      }
    }
  }
#endif
