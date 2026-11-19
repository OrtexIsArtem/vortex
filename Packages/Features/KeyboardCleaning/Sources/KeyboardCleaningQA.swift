#if DEBUG
  import ComposableArchitecture
  import VortexCore
  import VortexPlatform

  extension KeyboardCleaningModule {
    private static var isRegistered = false

    /// QA mode's `keyboard` command, which stands for the user:
    /// - `press=start`: the utility's action as its shortcut runs it, which the shell runs with the window open (its
    ///   button in Home's dock is `utilities press id=keyboard.lock`);
    /// - `press=stop`: «Turn the keyboard back on» on the lock screen;
    /// - `key=<name>`: a key of the locked keyboard going down, by its `KeyboardKey` name (a, digit1, f1, leftShift,
    ///   return, upArrow, section…);
    /// - `press=turnOn|restart`: the Accessibility row on its settings page.
    /// The state section `keyboard` has whether the keys are locked, the board the lock screen draws and how washed each
    /// pressed key looks.
    static func registerQACommands() {
      guard QA.isActive, !isRegistered else { return }
      isRegistered = true
      QA.registerState(section: "keyboard") { QAState(store.state) }
      QA.register(command: "keyboard") { arguments in
        let pressedRow = try QAPermissions.pressRow(
          arguments,
          needs: permissionNeeds,
          statuses: store.statuses,
          turnOn: { store.send(.turnOnTapped($0)) },
          restart: { store.send(.restartTapped) }
        )
        if pressedRow { return }
        if let name = arguments["key"] {
          guard store.isLocked else { throw QAError("the keyboard is not locked") }
          guard let key = KeyboardKey.allCases.first(where: { "\($0)" == name }) else {
            throw QAError("no key \(name); keys: \(KeyboardKey.allCases.map { "\($0)" }.joined(separator: ", "))")
          }
          guard QA.pressKey(key) > 0 else { throw QAError("nothing listens for the locked keyboard yet") }
          return
        }
        switch arguments["press"] {
        case "start":
          guard QA.pressHotkey(Hotkey.lockKeyboard.name) > 0 else {
            throw QAError("nobody listens for the shortcut \(Hotkey.lockKeyboard.name): keyboard cleaning doesn't run")
          }
        case "stop":
          guard store.isLocked else { throw QAError("the keyboard is not locked") }
          store.send(.stopTapped)
        default:
          throw QAError("keyboard takes press=start|stop|turnOn|restart or key=<name>")
        }
      }
    }

    /// Keyboard cleaning in the state dump.
    struct QAState: Encodable {
      var isLocked: Bool
      /// The board the lock screen draws: ansi, iso or jis (drawn as ansi).
      var layout: String
      /// How washed each pressed key looks, 1 to 3, by `KeyboardKey` name.
      var washes: [String: Int]

      init(_ state: KeyboardCleaningFeature.State) {
        isLocked = state.isLocked
        layout = state.layout.rawValue
        washes = Dictionary(uniqueKeysWithValues: state.presses.keys.map { ("\($0)", state.washes(of: $0)) })
      }
    }
  }
#endif
