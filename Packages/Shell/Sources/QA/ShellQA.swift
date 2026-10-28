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
      QA.registerState(section: "shell") { State(store: store, window: window) }
      QA.register(command: "entry") { arguments in
        try perform(Entry(arguments), store: store, window: window)
      }
      QA.register(command: "tab") { arguments in try selectTab(arguments, store: store) }
      QA.register(command: "keyboard") { arguments in try pressKeyboard(arguments, store: store) }
      QA.register(command: "screens") { arguments in
        guard let text = arguments["set"], let screens = QALaunch.screens(text) else {
          throw QAError("screens takes set=notch, set=plain or set=notch+plain")
        }
        QA.screens = screens
        window.qaScreensChanged()
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
        guard let index = menu.items.firstIndex(where: { $0.identifier?.rawValue == identifier }) else {
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

    /// `tab id=<feature id>|settings [section=general|activation|features]`: a click on the sidebar, in the open window.
    static func selectTab(_ arguments: [String: String], store: StoreOf<ShellFeature>) throws {
      guard store.isOpen else { throw QAError("the window is closed") }
      guard let id = arguments["id"] else { throw QAError("tab needs id=<feature id> or id=settings") }
      let tab: ShellFeature.Tab = id == "settings" ? .settings : .feature(id)
      guard store.state.isAvailable(tab) else {
        throw QAError("no tab \(id); tabs: \((store.sidebarFeatures.map(\.id) + ["settings"]).joined(separator: ", "))")
      }
      store.send(.tabSelected(tab))
      if let name = arguments["section"] {
        guard tab == .settings, let section = ShellFeature.SettingsSection.allCases.first(where: { "\($0)" == name }) else {
          throw QAError("section= goes with id=settings and is general, activation or features")
        }
        store.send(.binding(.set(\.settingsSection, section)))
      }
    }

    /// `keyboard press=start`: Home's keyboard button, on Home in the open window; `keyboard press=stop`:
    /// «Увімкнути клавіатуру» on the lock screen.
    static func pressKeyboard(_ arguments: [String: String], store: StoreOf<ShellFeature>) throws {
      switch arguments["press"] {
      case "start":
        guard store.isOpen, store.selectedTab == .feature("home") else {
          throw QAError("the keyboard button is on Home, in the open window")
        }
        store.send(.keyboardCleaning(.startTapped))
      case "stop":
        guard store.keyboardCleaning.isLocked else { throw QAError("the keyboard is not locked") }
        store.send(.keyboardCleaning(.stopTapped))
      default:
        throw QAError("keyboard takes press=start or press=stop")
      }
    }

    // MARK: - State

    /// The shell's part of the state dump.
    struct State: Encodable {
      var isOpen: Bool
      var openReason: String?
      var selectedTab: String
      var settingsSection: String
      /// Enabled features, in sidebar order.
      var sidebar: [FeatureID]
      var fileFeature: FeatureID?
      var keyboardLocked: Bool
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
        sidebar = state.sidebarFeatures.map(\.id)
        fileFeature = state.fileFeature?.id
        keyboardLocked = state.keyboardCleaning.isLocked
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
    }
  }
#endif
