#if DEBUG
  import AppKit
  import ComposableArchitecture
  import VortexCore

  // The only QA file that names the command client, in two lines that scripts/check-no-network.sh allows: the stand-in's
  // declaration and taking the client's place. Starting a process stays forbidden here too.

  extension DependencyValues {
    /// QA mode: every system client whose effect reaches past the run's own folder, replaced. Each starts from its
    /// unimplemented value with every endpoint set here, so an endpoint added later is a violation in the state dump,
    /// never the live one.
    mutating func useQAClients() {
      activeAppClient = .qa
      appsClient = .qa
      commandClient = .qa
      fileClient = .qa
      frontWindowClient = .qa
      hotkeyClient = .qa
      keyboardLockClient = .qa
      keychainClient = .qa
      launchAtLoginClient = .qa
      notificationClient = .qa
      pasteboardClient = .qa
      quickLookClient = .qa
      screenCaptureClient = .qa
      soundClient = .qa
      systemClient = .qa
      textRecognitionClient = .qa
    }
  }

  private var simulation: QASimulation { QASimulation.current.value }

  extension ActiveAppClient {
    /// The app in front is `frontApp`; `app activate=`, `app quit=` and `app frames=` move apps and their windows.
    static let qa: ActiveAppClient = {
      var client = ActiveAppClient()
      client.activations = { QASystem.shared.activations() }
      client.terminations = { QASystem.shared.terminations() }
      client.frontmost = { simulation.frontApp }
      client.windowFrames = { bundleID in QASystem.shared.windowFrames(of: bundleID) }
      return client
    }()
  }

  extension AppsClient {
    /// Running apps from fixtures; the picker returns `chooseApp` without showing; opening an app is only logged.
    static let qa: AppsClient = {
      var client = AppsClient()
      client.running = { QAFixtures.runningApps }
      client.choose = {
        let picked = simulation.chooseApp.map { AppInfo(bundleID: $0, name: QAFixtures.name(of: $0)) }
        QALog.record("apps", "choose", ["shown": "nothing", "picked": picked?.bundleID ?? "cancel"])
        return picked
      }
      client.open = { bundleID, url in
        QALog.record("apps", "open", ["bundleID": bundleID, "url": url?.absoluteString ?? ""])
      }
      return client
    }()
  }

  // The type is named only on the next line and in `useQAClients`: scripts/check-no-network.sh allows those two.
  extension CommandClient {
    /// Nothing runs: the first `sim shell` script whose text the command contains answers, otherwise exit 0 and no
    /// output. A script whose delay reaches the time limit ends as the live client ends such a command: exit 143,
    /// timed out. Values in the simulated keychain are taken out of the log.
    static let qa = qa { simulation.commandRules }

    static func qa(scripts: @escaping @Sendable () -> [QASimulation.CommandRule]) -> Self {
      var client = Self()
      client.run = { command, directory, environment, timeout in
        let rule = scripts().first { command.contains($0.match) }
        let delay = rule?.delay ?? 0
        let timedOut = delay > 0 && delay >= timeout.inSeconds
        if delay > 0 {
          try await Task.sleep(for: .seconds(min(delay, timeout.inSeconds)))
        }
        let stdout = (rule?.echo == true ? command + "\n" : "") + (rule?.stdout ?? "")
        let output = timedOut
          ? Output(exitCode: 128 + SIGTERM, stdout: Data(stdout.utf8), stderr: Data((rule?.stderr ?? "").utf8), timedOut: true)
          : Output(exitCode: rule?.exitCode ?? 0, stdout: Data(stdout.utf8), stderr: Data((rule?.stderr ?? "").utf8))
        QALog.record("command", "run", [
          "command": command,
          "directory": directory?.path ?? "~",
          "environment": environment.keys.sorted().joined(separator: " "),
          "exit": "\(output.exitCode)",
          "script": rule?.match ?? "",
        ])
        return output
      }
      return client
    }
  }

  extension FileClient {
    /// The real files inside the run's folder and the temporary folders; anything else is refused, as if missing.
    /// Finder, opening a file or page and the folder picker are only logged: the picker returns `chooseFolder`.
    static let qa: FileClient = {
      let live = FileClient.liveValue
      @Sendable func allowed(_ url: URL, _ operation: String) -> Bool {
        guard QAPaths.isSafe(url) else {
          QALog.record("files", "refused: \(operation) outside the QA folder", ["path": url.path])
          return false
        }
        return true
      }
      let refused = QAError("outside the QA folder")
      var client = FileClient()
      client.info = { url in allowed(url, "info") ? await live.info(url) : nil }
      client.contents = { folder in allowed(folder, "contents") ? await live.contents(folder) : [] }
      client.read = { url in
        guard allowed(url, "read") else { throw refused }
        return try await live.read(url)
      }
      client.write = { data, url in
        guard allowed(url, "write") else { throw refused }
        try await live.write(data, url)
      }
      client.copy = { from, to in
        guard allowed(from, "copy from"), allowed(to, "copy to") else { throw refused }
        try await live.copy(from, to)
      }
      client.remove = { url in
        guard allowed(url, "remove") else { return }
        await live.remove(url)
      }
      client.revealInFinder = { urls in
        QALog.record("files", "revealInFinder", ["paths": urls.map(\.path).joined(separator: "\n")])
      }
      client.open = { url in
        QALog.record("files", "open", ["url": url.isFileURL ? url.path : url.absoluteString])
      }
      client.chooseFolder = {
        let picked = simulation.chooseFolder.map { URL(fileURLWithPath: $0, isDirectory: true) }
        QALog.record("files", "chooseFolder", ["shown": "nothing", "picked": picked?.path ?? "cancel"])
        return picked
      }
      client.changes = { folder in allowed(folder, "watch") ? live.changes(folder) : .finished }
      return client
    }()
  }

  extension FrontWindowClient {
    /// The app, title and page `sim set frontApp= frontTitle= frontURL=` give.
    static let qa: FrontWindowClient = {
      var client = FrontWindowClient()
      client.current = {
        let simulation = simulation
        QALog.record("frontWindow", "current", ["app": simulation.frontApp])
        return FrontWindow(
          app: AppInfo(bundleID: simulation.frontApp, name: QAFixtures.name(of: simulation.frontApp)),
          windowTitle: simulation.frontTitle,
          url: simulation.frontURL.flatMap(URL.init(string:))
        )
      }
      return client
    }()
  }

  extension HotkeyClient {
    /// Nothing is registered with the system; `entry kind=hotkey id=<name>` presses a shortcut.
    static let qa: HotkeyClient = {
      var client = HotkeyClient()
      client.presses = { hotkey in QASystem.shared.presses(hotkey.name) }
      return client
    }()
  }

  extension KeyboardLockClient {
    /// Never a real event tap: the lock holds when `keyboardAccess` is on and `keyboardLockRefuses` off; asking for
    /// access shows nothing.
    static let qa: KeyboardLockClient = {
      var client = KeyboardLockClient()
      client.hasAccess = { simulation.keyboardAccess }
      client.requestAccess = { QALog.record("keyboardLock", "requestAccess", ["shown": "nothing"]) }
      client.lock = {
        let isLocked = simulation.keyboardAccess && !simulation.keyboardLockRefuses
        QALog.record("keyboardLock", "lock", ["locked": "\(isLocked)"])
        return isLocked
      }
      client.unlock = { QALog.record("keyboardLock", "unlock") }
      return client
    }()
  }

  extension KeychainClient {
    /// In memory, gone when the run quits. Every value is taken out of the log and the state.
    static let qa: KeychainClient = {
      var client = KeychainClient()
      client.save = { service, account, value, _ in
        QALog.secrets.withValue { _ = $0.insert(value) }
        QASystem.shared.keychain.withValue { $0[service, default: [:]][account] = value }
        QALog.record("keychain", "save", ["service": service, "account": account])
      }
      client.read = { service, account in QASystem.shared.keychain.value[service]?[account] }
      client.delete = { service, account in
        QASystem.shared.keychain.withValue { $0[service]?[account] = nil }
        QALog.record("keychain", "delete", ["service": service, "account": account])
      }
      client.accounts = { service in (QASystem.shared.keychain.value[service] ?? [:]).keys.sorted() }
      return client
    }()
  }

  extension LaunchAtLoginClient {
    /// The login item is `launchAtLogin` in the simulation; System Settings is only logged. The first launch registers
    /// it only with `--qa-release`, as only release builds do.
    static let qa: LaunchAtLoginClient = {
      @Sendable func status() -> LaunchAtLoginStatus {
        switch simulation.launchAtLogin {
        case "enabled": .enabled
        case "requiresApproval": .requiresApproval
        default: .disabled
        }
      }
      var client = LaunchAtLoginClient()
      client.status = { status() }
      client.setEnabled = { isEnabled in
        QASimulation.update { $0.launchAtLogin = isEnabled ? "enabled" : "disabled" }
        QALog.record("launchAtLogin", isEnabled ? "register" : "unregister")
        return status()
      }
      client.enableOnFirstLaunch = {
        guard QA.releaseBehavior, !simulation.launchAtLoginSetUp else {
          QALog.record("launchAtLogin", "enableOnFirstLaunch", ["registered": "no"])
          return
        }
        QASimulation.update {
          $0.launchAtLoginSetUp = true
          $0.launchAtLogin = "enabled"
        }
        QALog.record("launchAtLogin", "enableOnFirstLaunch", ["registered": "yes"])
      }
      client.openSystemSettings = { QALog.record("launchAtLogin", "openSystemSettings") }
      return client
    }()
  }

  extension NotificationClient {
    /// Nothing reaches Notification Center: requests answer `notificationsAllowed`, posts are logged, and
    /// `sim press` presses a button.
    static let qa: NotificationClient = {
      var client = NotificationClient()
      client.requestAuthorization = {
        let isAllowed = simulation.notificationsAllowed
        QALog.record("notifications", "requestAuthorization", ["shown": "nothing", "answer": "\(isAllowed)"])
        return isAllowed
      }
      client.post = { id, title, body, buttons in
        QALog.record("notifications", "post", [
          "id": id,
          "title": title,
          "body": body,
          "buttons": buttons.map(\.id).joined(separator: ","),
          "shown": "\(simulation.notificationsAllowed)",
        ])
      }
      client.remove = { prefix in QALog.record("notifications", "remove", ["prefix": prefix]) }
      client.buttonPresses = { QASystem.shared.buttonPresses() }
      return client
    }()
  }

  extension PasteboardClient {
    /// In memory: `sim copy` copies in another app; what Vortex writes stays here.
    static let qa: PasteboardClient = {
      var client = PasteboardClient()
      client.copies = { QASystem.shared.copies() }
      client.write = { content, isConcealed, source in
        QASystem.shared.write(content, isConcealed: isConcealed, source: source)
      }
      return client
    }()
  }

  extension QuickLookClient {
    /// The Quick Look panel never shows.
    static let qa: QuickLookClient = {
      var client = QuickLookClient()
      client.toggle = { urls in QALog.record("quickLook", "toggle", ["paths": urls.map(\.path).joined(separator: "\n")]) }
      client.close = { QALog.record("quickLook", "close") }
      return client
    }()
  }

  extension ScreenCaptureClient {
    /// A capture sees fixtures/screen.png, or a plain picture, as the main display; only with `screenAccess` on.
    static let qa: ScreenCaptureClient = {
      var client = ScreenCaptureClient()
      client.hasAccess = { simulation.screenAccess }
      client.requestAccess = {
        QALog.record("screenCapture", "requestAccess", ["shown": "nothing", "answer": "\(simulation.screenAccess)"])
        return simulation.screenAccess
      }
      client.captureScreenUnderPointer = {
        guard simulation.screenAccess else {
          QALog.record("screenCapture", "capture", ["result": "no access"])
          throw QAError("Screen Recording is off in the simulation")
        }
        let screenshot = await QAFixtures.screenshot()
        QALog.record("screenCapture", "capture", [
          "size": "\(Int(screenshot.image.size.width))×\(Int(screenshot.image.size.height))",
        ])
        return screenshot
      }
      return client
    }()
  }

  extension SoundClient {
    /// The real list of names; nothing plays.
    static let qa: SoundClient = {
      var client = SoundClient()
      client.names = { SystemSounds.names() }
      client.play = { name in QALog.record("sound", "play", ["name": name]) }
      return client
    }()
  }

  extension SystemClient {
    /// The theme as in the app, which touches only this process; the language from the launch arguments, a new one
    /// kept for the next relaunch; relaunch and quit through QA, after the reply.
    static let qa: SystemClient = {
      let live = SystemClient.liveValue
      var client = SystemClient()
      client.applyTheme = { theme in await live.applyTheme(theme) }
      client.language = { QALifecycle.launchLanguage() }
      client.setLanguage = { language in
        QALifecycle.nextLanguage.setValue(language)
        QALog.record("system", "setLanguage", ["language": language.rawValue])
      }
      client.relaunch = { await QA.relaunch() }
      client.quit = {
        QALog.record("system", "quit")
        await QA.quit()
      }
      return client
    }()
  }

  extension TextRecognitionClient {
    /// Every image says `recognizedText`.
    static let qa: TextRecognitionClient = {
      var client = TextRecognitionClient()
      client.recognize = { image in
        QALog.record("textRecognition", "recognize", ["size": "\(Int(image.size.width))×\(Int(image.size.height))"])
        return simulation.recognizedText
      }
      return client
    }()
  }

  private extension Duration {
    var inSeconds: Double {
      Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
  }
#endif
