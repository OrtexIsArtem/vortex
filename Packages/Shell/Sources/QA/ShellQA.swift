#if DEBUG
  import AppKit
  import ComposableArchitecture
  import VortexCore
  import VortexPlatform

  /// The shell's part of QA mode (VortexPlatform's `QA`): commands for what the user does at the notch, the menu bar
  /// icon, the window and its sidebar; the shell's state; the notch window for snapshots.
  @MainActor
  enum ShellQA {
    static func install(store: StoreOf<ShellFeature>) {
      let window = WindowController.shared
      QA.registerWindow(id: "notch", mode: { store.openReason.map { "\($0)" } }) { window.qaPanel }
      QA.registerWindow(id: "ears") { window.qaEarsWindow() }
      QA.registerState(section: "shell") { State(store: store, window: window) }
      PermissionsQA.install(store: store)
      QA.register(command: "entry") { arguments in
        try perform(Entry(arguments), store: store, window: window)
      }
      QA.register(command: "tab") { arguments in try selectTab(arguments, store: store) }
      QA.register(command: "screens") { arguments in
        guard let text = arguments["set"], let screens = QALaunch.screens(text) else {
          throw QAError("screens takes set=notch, set=plain or set=notch+plain")
        }
        QA.screens = screens
        window.qaScreensChanged()
      }
      QA.register(command: "catalog") { arguments in try catalog(arguments, store: store) }
      QA.register(command: "feature") { arguments in try feature(arguments, store: store) }
      QA.register(command: "utility") { arguments in try pressUtility(arguments, store: store) }
      QA.register(command: "utilities") { arguments in try utilities(arguments, store: store) }
      QA.registerState(section: "utilities") { UtilitiesState(store.state) }
      QA.register(command: "launch") { arguments in
        guard let word = arguments["set"] else { throw QAError("launch takes set=normal|safe|stop:<feature id>") }
        try LaunchQA.setNextVerdict(word)
      }
      QA.register(command: "indicator") { _ in
        @Shared(.notchIndicators) var indicators
        $indicators.withLock { indicators in
          indicators["debug"] = indicators["debug"] == nil
            ? NotchIndicator(leading: [.progress(0.7)], trailing: [.text("8:42")])
            : nil
        }
      }
    }

    // MARK: - The catalog

    /// `catalog open`: the sidebar's catalog icon; `catalog page id=<feature id>`: a card or a utility's row, onto its
    /// page; `catalog switch id=<utility id> on=true|false`: a utility's switch in the Utilities section, on the list. In
    /// the open window only, as a click would be.
    static func catalog(_ arguments: [String: String], store: StoreOf<ShellFeature>) throws {
      guard store.isOpen else { throw QAError("the window is closed") }
      if arguments["open"] != nil {
        store.send(.tabSelected(.catalog))
      } else if arguments["page"] != nil, let id = arguments["id"] {
        guard store.state.isAvailable(.catalogPage(id)) else {
          throw QAError("no page for \(id); the catalog has \(store.catalogFeatures.map(\.id).joined(separator: ", "))")
        }
        store.send(.tabSelected(.catalogPage(id)))
      } else if arguments["switch"] != nil, let id = arguments["id"], let isOn = arguments["on"].flatMap(Bool.init) {
        guard store.selectedTab == .catalog else { throw QAError("the catalog's list doesn't show: `catalog open` first") }
        guard let utility = store.catalogUtilities.first(where: { $0.id == id }) else {
          let ids = store.catalogUtilities.map(\.id)
          throw QAError("no utility \(id); the Utilities section has \(ids.isEmpty ? "none" : ids.joined(separator: ", "))")
        }
        guard utility.suspension == nil else { throw QAError("\(id) is paused: its switch doesn't move") }
        store.send(.utilitySwitched(id, isOn: isOn))
      } else {
        throw QAError("catalog takes open, page id=<feature id>, or switch id=<utility id> on=true|false")
      }
    }

    /// `feature add|remove|erase|home|settings id=<feature id>`: the buttons of the feature's page, which must show it;
    /// `home` is "Add to Home", `settings` goes to the feature's page in Settings › Features. Erase confirms at once
    /// and goes the real way: the feature is left to erase and the run relaunches.
    static func feature(_ arguments: [String: String], store: StoreOf<ShellFeature>) throws {
      guard let id = arguments["id"] else {
        throw QAError("feature takes add, remove, erase, home or settings, with id=<feature id>")
      }
      guard store.isOpen, store.selectedTab == .catalogPage(id), let page = store.state.pageState(id) else {
        throw QAError("\(id)'s page doesn't show: `catalog page id=\(id)` first")
      }
      if arguments["add"] != nil {
        switch page {
        case .available, .removed: store.send(.featureAdded(id))
        default: throw QAError("\(id)'s page has no Add")
        }
      } else if arguments["remove"] != nil {
        switch page {
        case .added, .stopped: store.send(.featureRemoved(id))
        default: throw QAError("\(id)'s page has no Remove")
        }
      } else if arguments["erase"] != nil {
        guard case .removed = page else { throw QAError("\(id)'s page has no Erase Data") }
        store.send(.eraseTapped(id))
        store.send(.eraseConfirmed)
      } else if arguments["home"] != nil {
        // The button stays after a request that found no room, to try again.
        guard [.canAdd, .noRoom].contains(store.state.homeOnPage(id)) else {
          throw QAError("\(id)'s page has no Add to Home")
        }
        store.send(.addToHomeTapped(id))
      } else if arguments["settings"] != nil {
        guard case .added = page, store.state.hasSettingsPage(id) else { throw QAError("\(id)'s page has no Settings") }
        store.send(.featureSettingsTapped(id))
      } else {
        throw QAError("feature takes add, remove, erase, home or settings, with id=<feature id>")
      }
    }

    // MARK: - Utility actions

    /// `utility press id=<action id>`: a running feature's utility action, run as a press of its button or its
    /// shortcut runs it: the window as the action needs it, then the action.
    static func pressUtility(_ arguments: [String: String], store: StoreOf<ShellFeature>) throws {
      guard arguments["press"] != nil, let id = arguments["id"] else {
        throw QAError("utility takes press id=<action id>")
      }
      guard store.utilityActions.contains(where: { $0.id == id }) else {
        let ids = store.utilityActions.map(\.id)
        throw QAError("no utility action \(id) runs; there are \(ids.isEmpty ? "none" : ids.joined(separator: ", "))")
      }
      store.send(.utilityActionPressed(id))
    }

    /// `utilities open|close`: Home's utilities button, in the open window on Home; `utilities press id=<action id>`: a
    /// button of the strip that is out, which puts it away and runs the action as its shortcut does. The strip's pencil
    /// is Home's: `home edit`.
    static func utilities(_ arguments: [String: String], store: StoreOf<ShellFeature>) throws {
      if arguments["open"] != nil {
        guard store.isOpen, case let .feature(id) = store.selectedTab,
              store.features.contains(where: { $0.id == id && $0.isBuiltIn })
        else { throw QAError("the utilities button is on Home, in the open window") }
        guard !store.isDockOpen else { throw QAError("the dock is out already") }
        guard !store.dockActions.isEmpty else { throw QAError("no utility runs, so the button is the pencil: `home edit`") }
        guard store.focusedFeature == nil else { throw QAError("Home's editor is open: the button hides") }
        store.send(.dockToggled)
      } else if arguments["close"] != nil {
        guard store.isDockOpen else { throw QAError("the dock isn't out") }
        store.send(.dockToggled)
      } else if arguments["press"] != nil, let id = arguments["id"] {
        guard store.isDockOpen else { throw QAError("the dock isn't out: `utilities open` first") }
        guard store.dockActions.contains(where: { $0.id == id }) else {
          throw QAError("the dock has no \(id); it has \(store.dockActions.map(\.id).joined(separator: ", "))")
        }
        store.send(.utilityActionPressed(id))
      } else {
        throw QAError("utilities takes open, close or press id=<action id>")
      }
    }

    /// The utilities dock in the state dump.
    struct UtilitiesState: Encodable {
      /// Home's button: "utilities", or "pencil" while no utility action runs.
      var button: String
      var isOpen: Bool
      /// The open window's size: regular, large or dock; "closed" while it is.
      var windowSize: String
      /// Its buttons in order: "<action id> <window need>", then " keys=<keys>" and " warning=<permission>" when set.
      var buttons: [String]

      init(_ state: ShellFeature.State) {
        button = state.dockActions.isEmpty ? "pencil" : "utilities"
        isOpen = state.isDockOpen
        windowSize = state.openWindowSize.map { "\($0)" } ?? "closed"
        buttons = state.dockActions.map { action in
          "\(action.id) \(action.window)"
            + (state.dockKeys[action.id].map { " keys=\($0)" } ?? "")
            + (state.dockWarning(action).map { " warning=\($0.rawValue)" } ?? "")
        }
      }
    }

    // MARK: - entry

    /// A way into Vortex, or something the user does at the window, as `entry kind=…` names it.
    enum Entry: Equatable {
      /// The pointer comes to the notch, over a feature's ear or the cutout, and stays.
      case hover(ear: FeatureID?)
      /// The pointer goes away from the notch and the window.
      case leave
      case earClick(FeatureID)
      case notchClick
      case menuBarClick
      /// An item of the menu bar icon's menu, by its identifier: open, settings, quit.
      case menu(String)
      /// A shortcut, by its `Hotkey` name: openVortex, open-<feature id>, or a feature's own.
      case hotkey(String)
      case pointer(inside: Bool)
      /// A click in another app.
      case outsideClick
      case escape
      /// Files dragged onto the notch.
      case drag
      /// A file dropped on the menu bar icon.
      case drop(URL)
      /// A file opened with Vortex, as `vortex shelf add` does.
      case open(URL)

      static let kinds = "hover, leave, ear, notch, menubar, menu, hotkey, pointer, outside, escape, drag, drop or open"

      init(_ arguments: [String: String]) throws {
        func value(_ key: String) throws -> String {
          guard let value = arguments[key], !value.isEmpty else {
            throw QAError("entry kind=\(arguments["kind"] ?? "") needs \(key)=")
          }
          return value
        }
        func file() throws -> URL {
          let path = try value("file")
          guard QA.isSafe(path: path) else { throw QAError("file= takes a file inside the QA folder or a temporary folder") }
          return URL(fileURLWithPath: path)
        }
        switch arguments["kind"] {
        case "hover": self = .hover(ear: arguments["ear"].flatMap { $0.isEmpty ? nil : $0 })
        case "leave": self = .leave
        case "ear": self = .earClick(try value("id"))
        case "notch": self = .notchClick
        case "menubar": self = .menuBarClick
        case "menu": self = .menu(try value("item"))
        case "hotkey": self = .hotkey(try value("id"))
        case "pointer":
          guard let inside = arguments["inside"].flatMap(Bool.init) else {
            throw QAError("entry kind=pointer needs inside=true or inside=false")
          }
          self = .pointer(inside: inside)
        case "outside": self = .outsideClick
        case "escape": self = .escape
        case "drag": self = .drag
        case "drop": self = .drop(try file())
        case "open": self = .open(try file())
        default: throw QAError("entry needs kind=\(Self.kinds)")
        }
      }
    }

    /// Does what the user would, and only what the user could: an ear must show to be clicked, the menu bar icon to be
    /// clicked or its menu chosen, and Esc reaches only a window that took the keyboard.
    static func perform(_ entry: Entry, store: StoreOf<ShellFeature>, window: WindowController) throws {
      func requireEar(_ feature: FeatureID) throws {
        let ears = window.qaEars
        guard !ears.isEmpty, [ears.leftFeature, ears.rightFeature].contains(feature) else {
          let shown = [ears.leftFeature, ears.rightFeature].compactMap(\.self)
          throw QAError("no ear of \(feature) shows; ears: \(shown.isEmpty ? "none" : Set(shown).sorted().joined(separator: ", "))")
        }
      }
      func requireMenuBarIcon() throws {
        guard window.qaIsMenuBarIconShown else { throw QAError("the menu bar icon is hidden") }
      }
      func requireNotch() throws {
        guard QA.screens.contains(.notch) else { throw QAError("no display has a notch: screens are \(QA.screens.map(\.rawValue).joined(separator: "+"))") }
      }
      switch entry {
      case .hover, .earClick, .notchClick, .drag:
        try requireNotch()
      default:
        break
      }
      switch entry {
      case let .hover(ear):
        if let ear { try requireEar(ear) }
        // Over the notch the pointer is inside the window that grows out of it.
        window.qaMovePointer(intoWindow: true)
        window.qaEmit(.notchPointerOver(feature: ear))
        window.qaEmit(.notchHoverChanged(isInside: true))
      case .leave:
        window.qaEmit(.notchHoverChanged(isInside: false))
        window.qaMovePointer(intoWindow: false)
      case let .earClick(feature):
        try requireEar(feature)
        window.qaMovePointer(intoWindow: true)
        window.qaEmit(.notchClicked(feature: feature))
      case .notchClick:
        window.qaMovePointer(intoWindow: true)
        window.qaEmit(.notchClicked(feature: nil))
      case .menuBarClick:
        try requireMenuBarIcon()
        window.qaMovePointer(intoWindow: false)
        window.qaEmit(.menuBarIconClicked)
      case let .menu(identifier):
        try requireMenuBarIcon()
        guard let menu = window.qaMenu else { throw QAError("there is no menu") }
        let identifiers = menu.items.compactMap { $0.identifier?.rawValue }
        guard let index = menu.items.firstIndex(where: { $0.identifier?.rawValue == identifier && !$0.isHidden }) else {
          throw QAError("no menu item \(identifier); items: \(identifiers.joined(separator: ", "))")
        }
        window.qaMovePointer(intoWindow: false)
        menu.performActionForItem(at: index)
      case let .hotkey(name):
        guard QA.pressHotkey(name) > 0 else { throw QAError("nobody listens for the shortcut \(name)") }
      case let .pointer(inside):
        window.qaMovePointer(intoWindow: inside)
      case .outsideClick:
        window.qaMovePointer(intoWindow: false)
        window.qaEmit(.clickedOutside)
      case .escape:
        guard let reason = store.openReason, !reason.isPassing else {
          throw QAError("Esc goes to the app in front: the window is closed or opened on the way past")
        }
        window.qaEmit(.escapePressed)
      case .drag:
        window.qaMovePointer(intoWindow: true)
        window.qaEmit(.fileDragEnteredNotch)
      case let .drop(file):
        try requireMenuBarIcon()
        window.qaEmit(.filesDroppedOnMenuBarIcon([file]))
      case let .open(file):
        store.send(.filesReceived([file]))
      }
    }

    // MARK: - The window's controls

    /// `tab id=<feature id>|settings|catalog|catalog:<feature id> [section=general|activation|features]
    /// [feature=<feature id>]`: a click on the sidebar, in the open window; `catalog:<id>` is the feature's page in the
    /// catalog; `section=` then clicks a segment of Settings, and `feature=` (with `section=features`) the feature's
    /// row there, after "‹ Features" if another feature's page shows, onto its page.
    static func selectTab(_ arguments: [String: String], store: StoreOf<ShellFeature>) throws {
      guard store.isOpen else { throw QAError("the window is closed") }
      guard let id = arguments["id"] else { throw QAError("tab needs id=<feature id>, settings, catalog or catalog:<id>") }
      let tab: ShellFeature.Tab = id == "settings" || id == "catalog" || id.hasPrefix("catalog:")
        ? ShellFeature.Tab(storageValue: id)
        : .feature(id)
      guard store.state.isAvailable(tab) else {
        let tabs = store.sidebarFeatures.map(\.id) + ["settings", "catalog"]
        throw QAError("no tab \(id); tabs: \(tabs.joined(separator: ", "))")
      }
      var section: ShellFeature.SettingsSection?
      if let name = arguments["section"] {
        guard tab == .settings, let named = ShellFeature.SettingsSection.allCases.first(where: { "\($0)" == name }) else {
          throw QAError("section= goes with id=settings and is general, activation or features")
        }
        section = named
      }
      let feature = arguments["feature"]
      if let feature {
        guard section == .features else { throw QAError("feature= goes with id=settings section=features") }
        guard store.state.hasSettingsPage(feature) else {
          let listed = store.settingsFeatures.map(\.id)
          let list = listed.isEmpty ? "nothing" : listed.joined(separator: ", ")
          throw QAError("no page for \(feature) in Settings › Features; it lists \(list)")
        }
      }
      store.send(.tabSelected(tab))
      if let section {
        store.send(.binding(.set(\.settingsSection, section)))
      }
      if let feature {
        if store.settingsPage != nil { store.send(.settingsBackTapped) }
        store.send(.settingsRowTapped(feature))
      }
    }

    // MARK: - State

    /// The shell's part of the state dump.
    struct State: Encodable {
      var isOpen: Bool
      var openReason: String?
      var selectedTab: String
      var settingsSection: String
      /// The feature whose page Settings › Features shows in that segment; null for the list.
      var settingsFeature: FeatureID?
      /// Enabled features, in sidebar order.
      var sidebar: [FeatureID]
      /// The running features' utility actions, in sidebar order: "<id> <window need>[ <shortcut>]".
      var utilityActions: [String]
      var fileFeature: FeatureID?
      /// The utility whose cover is over the window, "<id>" with " holdsKeyboard" when Vortex holds the keyboard for it;
      /// null without one. Keyboard cleaning's own state is its `keyboard` section.
      var cover: String?
      var screens: [String]
      var everyScreenHasNotch: Bool
      /// Whether the menu bar icon would show; QA puts none in the menu bar.
      var menuBarIcon: Bool
      var ears: [String: FeatureID]
      var hoveredEar: FeatureID?
      var pointerInWindow: Bool
      var heldOpen: Bool
      var launchAtLogin: String
      var language: String
      var needsRestartForLanguage: Bool
      var settings: ShellSettings

      @MainActor
      init(store: StoreOf<ShellFeature>, window: WindowController) {
        let state = store.state
        let ears = window.qaEars
        isOpen = state.isOpen
        openReason = state.openReason.map { "\($0)" }
        selectedTab = state.selectedTab.storageValue
        settingsSection = "\(state.settingsSection)"
        settingsFeature = state.settingsPage?.id
        sidebar = state.sidebarFeatures.map(\.id)
        utilityActions = state.utilityActions.map { action in
          "\(action.id) \(action.window)" + (action.shortcut.map { " \($0)" } ?? "")
        }
        fileFeature = state.fileFeature?.id
        cover = state.windowCover.map { $0.feature + ($0.holdsKeyboard ? " holdsKeyboard" : "") }
        screens = QA.screens.map(\.rawValue)
        everyScreenHasNotch = state.everyScreenHasNotch
        menuBarIcon = window.qaIsMenuBarIconShown
        self.ears = ["left": ears.leftFeature, "right": ears.rightFeature].compactMapValues(\.self)
        hoveredEar = state.hoveredEar
        pointerInWindow = window.qaIsPointerInWindow
        heldOpen = state.isHeldOpen
        launchAtLogin = "\(state.launchAtLogin)"
        language = state.language.rawValue
        needsRestartForLanguage = state.needsRestartForLanguage
        settings = state.settings
      }

      private enum CodingKeys: String, CodingKey {
        case isOpen, openReason, selectedTab, settingsSection, settingsFeature, sidebar, utilityActions, fileFeature, cover
        case screens, everyScreenHasNotch, menuBarIcon, ears, hoveredEar, pointerInWindow, heldOpen
        case launchAtLogin, language, needsRestartForLanguage, settings
      }

      /// Every key, `null` for what is absent, so a reader never has to tell a missing key from a closed window.
      func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isOpen, forKey: .isOpen)
        try container.encode(openReason, forKey: .openReason)
        try container.encode(selectedTab, forKey: .selectedTab)
        try container.encode(settingsSection, forKey: .settingsSection)
        try container.encode(settingsFeature, forKey: .settingsFeature)
        try container.encode(sidebar, forKey: .sidebar)
        try container.encode(utilityActions, forKey: .utilityActions)
        try container.encode(fileFeature, forKey: .fileFeature)
        try container.encode(cover, forKey: .cover)
        try container.encode(screens, forKey: .screens)
        try container.encode(everyScreenHasNotch, forKey: .everyScreenHasNotch)
        try container.encode(menuBarIcon, forKey: .menuBarIcon)
        try container.encode(ears, forKey: .ears)
        try container.encode(hoveredEar, forKey: .hoveredEar)
        try container.encode(pointerInWindow, forKey: .pointerInWindow)
        try container.encode(heldOpen, forKey: .heldOpen)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(language, forKey: .language)
        try container.encode(needsRestartForLanguage, forKey: .needsRestartForLanguage)
        try container.encode(settings, forKey: .settings)
      }
    }
  }
#endif
