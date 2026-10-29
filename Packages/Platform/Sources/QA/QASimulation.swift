#if DEBUG
  import ComposableArchitecture
  import Foundation

  /// What the simulated system services of a QA run answer. Kept in DataFolder/.qa/simulation.json, so a relaunch
  /// keeps it; changed with the `sim set` command. Missing or unreadable keys fall back to their defaults.
  struct QASimulation: Codable, Equatable, Sendable {
    /// Accessibility for keyboard cleaning, until the simulated permissions arrive (stage 7, task 4).
    var keyboardAccess = false
    /// macOS refuses the lock though access reads on, as it does when the switch in System Settings went stale.
    var keyboardLockRefuses = false
    /// Screen Recording for screenshots, until the simulated permissions arrive.
    var screenAccess = false
    /// The answer to the notifications prompt, until the simulated permissions arrive.
    var notificationsAllowed = false
    /// enabled, disabled or requiresApproval.
    var launchAtLogin = "disabled"
    /// The first launch of a release build has registered the login item (only with `--qa-release`).
    var launchAtLoginSetUp = false
    /// The app in front: the front window service and the active app service both report it; `app activate=` and
    /// `app quit=` change it.
    var frontApp = "com.apple.TextEdit"
    var frontTitle: String? = "QA document"
    var frontURL: String?
    /// Windows of other apps by bundle id, front to back, as x, y, width, height in AppKit's screen coordinates:
    /// `app frames=`.
    var windowFrames: [String: [[Double]]] = [:]
    /// What the folder picker returns without showing; nil is Cancel.
    var chooseFolder: String?
    /// The bundle id the app picker returns without showing; nil is Cancel.
    var chooseApp: String?
    /// What text recognition finds on any image.
    var recognizedText = "QA text"
    /// Results of commands, the first whose `match` the command contains; without one a command exits 0, silent.
    var commandRules: [CommandRule] = []

    struct CommandRule: Codable, Equatable, Sendable {
      var match: String
      var exitCode: Int32
      var stdout: String
      var stderr: String
      /// Seconds the command takes, at most its time limit.
      var delay: Double = 0
      /// The output starts with the command itself, secrets and all, as some tools print what they run.
      var echo = false

      init(match: String, exitCode: Int32, stdout: String = "", stderr: String = "", delay: Double = 0, echo: Bool = false) {
        self.match = match
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.delay = delay
        self.echo = echo
      }

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        match = try container.decode(String.self, forKey: .match)
        exitCode = (try? container.decodeIfPresent(Int32.self, forKey: .exitCode)) ?? 0
        stdout = (try? container.decodeIfPresent(String.self, forKey: .stdout)) ?? ""
        stderr = (try? container.decodeIfPresent(String.self, forKey: .stderr)) ?? ""
        delay = (try? container.decodeIfPresent(Double.self, forKey: .delay)) ?? 0
        echo = (try? container.decodeIfPresent(Bool.self, forKey: .echo)) ?? false
      }
    }

    init() {}

    init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let defaults = QASimulation()
      func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
        (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
      }
      keyboardAccess = value(.keyboardAccess, defaults.keyboardAccess)
      keyboardLockRefuses = value(.keyboardLockRefuses, defaults.keyboardLockRefuses)
      screenAccess = value(.screenAccess, defaults.screenAccess)
      notificationsAllowed = value(.notificationsAllowed, defaults.notificationsAllowed)
      launchAtLogin = value(.launchAtLogin, defaults.launchAtLogin)
      launchAtLoginSetUp = value(.launchAtLoginSetUp, defaults.launchAtLoginSetUp)
      frontApp = value(.frontApp, defaults.frontApp)
      frontTitle = value(.frontTitle, defaults.frontTitle)
      frontURL = value(.frontURL, defaults.frontURL)
      windowFrames = value(.windowFrames, defaults.windowFrames)
      chooseFolder = value(.chooseFolder, defaults.chooseFolder)
      chooseApp = value(.chooseApp, defaults.chooseApp)
      recognizedText = value(.recognizedText, defaults.recognizedText)
      commandRules = value(.commandRules, defaults.commandRules)
    }

    /// Sets the values `sim set` names; an unknown key or a bad value is an error and changes nothing.
    mutating func set(_ values: [String: String]) throws {
      var copy = self
      for (key, value) in values.sorted(by: { $0.key < $1.key }) {
        func flag() throws -> Bool {
          guard let flag = Bool(value) else { throw QAError("\(key) takes true or false, not \"\(value)\"") }
          return flag
        }
        func text() -> String? { value.isEmpty ? nil : value }
        switch key {
        case "keyboardAccess": copy.keyboardAccess = try flag()
        case "keyboardLockRefuses": copy.keyboardLockRefuses = try flag()
        case "screenAccess": copy.screenAccess = try flag()
        case "notificationsAllowed": copy.notificationsAllowed = try flag()
        case "launchAtLogin":
          guard ["enabled", "disabled", "requiresApproval"].contains(value) else {
            throw QAError("launchAtLogin takes enabled, disabled or requiresApproval, not \"\(value)\"")
          }
          copy.launchAtLogin = value
        case "frontApp": copy.frontApp = value
        case "frontTitle": copy.frontTitle = text()
        case "frontURL": copy.frontURL = text()
        case "chooseFolder": copy.chooseFolder = text()
        case "chooseApp": copy.chooseApp = text()
        case "recognizedText": copy.recognizedText = value
        default:
          throw QAError(
            "sim set knows keyboardAccess, keyboardLockRefuses, screenAccess, notificationsAllowed, launchAtLogin, "
              + "frontApp, frontTitle, frontURL, chooseFolder, chooseApp and recognizedText, not \(key)"
          )
        }
      }
      self = copy
    }

    // MARK: - The run's simulation

    static let current = LockIsolated(QASimulation())

    static func load() {
      guard let data = try? Data(contentsOf: QAPaths.simulationFile),
            let loaded = try? JSONDecoder().decode(QASimulation.self, from: data)
      else { return }
      current.setValue(loaded)
    }

    /// Changes the simulation, and keeps it in the run's folder, in the order the changes came; outside QA mode, as in
    /// tests, only in memory.
    static func update(_ change: @Sendable (inout QASimulation) throws -> Void) rethrows {
      try current.withValue { simulation in
        try change(&simulation)
        guard QA.isActive else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(simulation).write(to: QAPaths.simulationFile, options: .atomic)
      }
    }
  }
#endif
