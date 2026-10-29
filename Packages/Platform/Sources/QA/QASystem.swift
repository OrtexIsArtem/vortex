#if DEBUG
  import AppKit
  import ComposableArchitecture
  import VortexCore

  /// The simulated system of a QA run: the pasteboard and the keychain in memory, shortcuts and notification buttons
  /// pressed by commands. `sim` scripts it.
  final class QASystem: Sendable {
    static let shared = QASystem()

    struct Clip: Sendable {
      var content: PasteboardContent
      var isConcealed: Bool
      var source: AppInfo?
      var changeCount: Int
    }

    /// What the simulated pasteboard holds; nil until something is copied.
    let pasteboard = LockIsolated<Clip?>(nil)
    /// Values by service, then account.
    let keychain = LockIsolated<[String: [String: String]]>([:])
    private let copyListeners = LockIsolated<[UUID: AsyncStream<PasteboardCopy>.Continuation]>([:])
    private let hotkeyListeners = LockIsolated<[UUID: (name: String, continuation: AsyncStream<Void>.Continuation)]>([:])
    private let pressListeners = LockIsolated<[UUID: AsyncStream<NotificationClient.Press>.Continuation]>([:])

    // MARK: - Pasteboard

    /// Copies made in other apps: only those `sim copy` makes.
    func copies() -> AsyncStream<PasteboardCopy> {
      AsyncStream { continuation in
        let id = UUID()
        copyListeners.withValue { $0[id] = continuation }
        continuation.onTermination = { _ in QASystem.shared.copyListeners.withValue { $0[id] = nil } }
      }
    }

    /// What Vortex puts on the pasteboard; like the real one, it never comes back as a copy.
    func write(_ content: PasteboardContent, isConcealed: Bool, source: AppInfo?) {
      let clip = pasteboard.withValue { clip in
        clip = Clip(content: content, isConcealed: isConcealed, source: source, changeCount: (clip?.changeCount ?? 0) + 1)
        return clip!
      }
      QALog.record("pasteboard", "write", ["content": Self.describe(clip), "source": source?.bundleID ?? ""])
    }

    /// A copy made in another app.
    func copy(_ copy: PasteboardCopy) {
      let clip = pasteboard.withValue { clip in
        clip = Clip(
          content: copy.content,
          isConcealed: copy.isConcealed,
          source: copy.source,
          changeCount: (clip?.changeCount ?? 0) + 1
        )
        return clip!
      }
      let listeners = copyListeners.value.values
      listeners.forEach { $0.yield(copy) }
      QALog.record("pasteboard", "copied in another app", [
        "content": Self.describe(clip),
        "listeners": "\(listeners.count)",
      ])
    }

    func pasteboardDump() -> Any {
      guard let clip = pasteboard.value else { return NSNull() }
      return [
        "changeCount": clip.changeCount,
        "concealed": clip.isConcealed,
        "source": clip.source?.bundleID ?? NSNull(),
        "content": Self.describe(clip),
      ] as [String: Any]
    }

    /// For the log and the state: never what a concealed item holds, never a secret.
    private static func describe(_ clip: Clip) -> String {
      guard !clip.isConcealed else { return "<concealed>" }
      let text = switch clip.content {
      case let .text(text): "text: " + (text.count > 200 ? text.prefix(200) + "…" : text)
      case let .link(url): "link: " + url.absoluteString
      case let .image(data): "image: \(data.count) bytes"
      case let .files(urls): "files: " + urls.map(\.path).joined(separator: ", ")
      }
      return QALog.redact(text)
    }

    // MARK: - Shortcuts

    /// Presses of a shortcut: only those `entry kind=hotkey` makes. Nothing is registered with the system.
    func presses(_ name: String) -> AsyncStream<Void> {
      AsyncStream { continuation in
        let id = UUID()
        hotkeyListeners.withValue { $0[id] = (name, continuation) }
        continuation.onTermination = { _ in QASystem.shared.hotkeyListeners.withValue { $0[id] = nil } }
      }
    }

    func pressHotkey(_ name: String) -> Int {
      let listeners = hotkeyListeners.value.values.filter { $0.name == name }
      listeners.forEach { $0.continuation.yield() }
      QALog.record("hotkey", "press", ["name": name, "listeners": "\(listeners.count)"])
      return listeners.count
    }

    /// The shortcuts someone listens for now.
    func hotkeyNames() -> [String] {
      Set(hotkeyListeners.value.values.map(\.name)).sorted()
    }

    // MARK: - Notification buttons

    func buttonPresses() -> AsyncStream<NotificationClient.Press> {
      AsyncStream { continuation in
        let id = UUID()
        pressListeners.withValue { $0[id] = continuation }
        continuation.onTermination = { _ in QASystem.shared.pressListeners.withValue { $0[id] = nil } }
      }
    }

    func press(_ press: NotificationClient.Press) -> Int {
      let listeners = pressListeners.value.values
      listeners.forEach { $0.yield(press) }
      QALog.record("notifications", "button pressed", [
        "notification": press.notification,
        "button": press.button,
        "listeners": "\(listeners.count)",
      ])
      return listeners.count
    }

    // MARK: - The `sim` command

    /// `sim` shows the simulation; `sim set key=value…` changes it; `sim copy text=|link=|file=|image= [concealed=true]
    /// [source=<bundle id>]` copies in another app; `sim press notification=<id> button=<id>` presses a notification's
    /// button; `sim shell match=<text> exit=<code> [stdout=] [stderr=] [delay=<seconds>] [echo=true]` scripts the commands
    /// that contain the text (a delay that reaches the time limit ends it there: exit 143, timed out);
    /// `sim shell clear` forgets the scripts.
    @MainActor
    func simulate(_ arguments: [String: String]) throws -> Any? {
      var values = arguments
      let actions = ["set", "copy", "press", "shell"].filter { values[$0] == "" }
      guard actions.count <= 1 else { throw QAError("sim takes one of set, copy, press or shell") }
      actions.first.map { values[$0] = nil }
      switch actions.first {
      case nil:
        guard values.isEmpty else { throw QAError("sim takes set, copy, press or shell") }
        return QAState.json(QASimulation.current.value)

      case "set":
        let changes = values
        try QASimulation.update { try $0.set(changes) }
        QALog.record("qa", "sim set", changes)
        return QAState.json(QASimulation.current.value)

      case "copy":
        copy(try Self.copy(from: values))
        return nil

      case "press":
        guard let notification = values["notification"], let button = values["button"] else {
          throw QAError("sim press needs notification=<id> button=<id>")
        }
        guard press(NotificationClient.Press(notification: notification, button: button)) > 0 else {
          throw QAError("nothing listens for notification buttons")
        }
        return nil

      default:
        if values["clear"] != nil {
          QASimulation.update { $0.commandRules = [] }
          return nil
        }
        let rule = try Self.rule(from: values)
        QASimulation.update { $0.commandRules.append(rule) }
        return QAState.json(QASimulation.current.value.commandRules)
      }
    }

    static func copy(from values: [String: String]) throws -> PasteboardCopy {
      let content: PasteboardContent
      if let text = values["text"] {
        content = .text(text)
      } else if let link = values["link"] {
        guard let url = URL(string: link), url.scheme != nil else { throw QAError("not a link: \(link)") }
        content = .link(url)
      } else if let file = values["file"] {
        // Like image=: a copied file is drawn and looked at, so it must be QA's.
        guard QAPaths.isSafe(file) else { throw QAError("file= takes a file inside the QA folder or a temporary folder") }
        content = .files([URL(fileURLWithPath: file)])
      } else if let image = values["image"] {
        guard QAPaths.isSafe(image), let data = FileManager.default.contents(atPath: image) else {
          throw QAError("image= takes a PNG file inside the QA folder or a temporary folder")
        }
        content = .image(data)
      } else {
        throw QAError("sim copy needs text=, link=, file= or image=")
      }
      let source = values["source"].map { AppInfo(bundleID: $0, name: QAFixtures.name(of: $0)) }
      let front = values["source"] ?? QASimulation.current.value.frontApp
      return PasteboardCopy(content: content, isConcealed: values["concealed"] == "true", source: source, frontApps: [front])
    }

    static func rule(from values: [String: String]) throws -> QASimulation.CommandRule {
      guard let match = values["match"], !match.isEmpty else {
        throw QAError("sim shell needs match=<text> and exit=<code>, or clear")
      }
      guard let exitCode = values["exit"].flatMap({ Int32($0) }) else { throw QAError("sim shell needs exit=<code>") }
      let delay = try values["delay"].map { text in
        guard let seconds = Double(text), seconds.isFinite, seconds >= 0 else {
          throw QAError("delay= takes seconds, not \(text)")
        }
        return seconds
      }
      return QASimulation.CommandRule(
        match: match,
        exitCode: exitCode,
        stdout: values["stdout"] ?? "",
        stderr: values["stderr"] ?? "",
        delay: delay ?? 0,
        echo: values["echo"] == "true"
      )
    }

    // MARK: - Apps in front

    private let activationListeners = LockIsolated<[UUID: AsyncStream<String>.Continuation]>([:])
    private let terminationListeners = LockIsolated<[UUID: AsyncStream<String>.Continuation]>([:])

    func activations() -> AsyncStream<String> {
      AsyncStream { continuation in
        let id = UUID()
        activationListeners.withValue { $0[id] = continuation }
        continuation.onTermination = { _ in QASystem.shared.activationListeners.withValue { $0[id] = nil } }
      }
    }

    func terminations() -> AsyncStream<String> {
      AsyncStream { continuation in
        let id = UUID()
        terminationListeners.withValue { $0[id] = continuation }
        continuation.onTermination = { _ in QASystem.shared.terminationListeners.withValue { $0[id] = nil } }
      }
    }

    /// The frames `app frames=` gave the app's windows.
    func windowFrames(of bundleID: String) -> [CGRect] {
      (QASimulation.current.value.windowFrames[bundleID] ?? []).compactMap { values in
        values.count == 4 ? CGRect(x: values[0], y: values[1], width: values[2], height: values[3]) : nil
      }
    }

    /// `app activate=<bundle id>` brings an app to the front; `app quit=<bundle id>` quits it, and Finder comes to the
    /// front if it was there; `app frames=<bundle id>:<x,y,w,h;…>` sets where its windows are, front to back, in AppKit's
    /// screen coordinates (nothing after the colon: no windows).
    @MainActor
    func app(_ arguments: [String: String]) throws {
      let known = Set(["activate", "quit", "frames"])
      guard !arguments.isEmpty, Set(arguments.keys).isSubset(of: known) else {
        throw QAError("app takes activate=<bundle id>, quit=<bundle id> or frames=<bundle id>:<x,y,w,h;…>")
      }
      if let frames = arguments["frames"] {
        let (bundleID, rects) = try Self.frames(frames)
        QASimulation.update { $0.windowFrames[bundleID] = rects.isEmpty ? nil : rects.map { [$0.minX, $0.minY, $0.width, $0.height] } }
        QALog.record("apps", "windows", ["bundleID": bundleID, "frames": "\(rects.count)"])
      }
      if let bundleID = arguments["quit"] {
        let wasInFront = QASimulation.current.value.frontApp == bundleID
        QASimulation.update { $0.windowFrames[bundleID] = nil }
        terminationListeners.value.values.forEach { $0.yield(bundleID) }
        QALog.record("apps", "quit", ["bundleID": bundleID])
        if wasInFront { activate(QAFixtures.finder) }
      }
      if let bundleID = arguments["activate"] {
        activate(bundleID)
      }
    }

    private func activate(_ bundleID: String) {
      QASimulation.update { $0.frontApp = bundleID }
      activationListeners.value.values.forEach { $0.yield(bundleID) }
      QALog.record("apps", "activate", ["bundleID": bundleID])
    }

    /// `com.apple.systempreferences:100,200,800,600;0,0,10,10` → the bundle id and its frames.
    static func frames(_ text: String) throws -> (bundleID: String, frames: [CGRect]) {
      guard let colon = text.firstIndex(of: ":"), colon != text.startIndex else {
        throw QAError("frames= takes <bundle id>:<x,y,w,h;…>, not \(text)")
      }
      let bundleID = String(text[..<colon])
      let list = text[text.index(after: colon)...]
      let frames = try list.split(separator: ";").map { part -> CGRect in
        let numbers = part.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 4, let x = numbers[0], let y = numbers[1], let width = numbers[2], let height = numbers[3],
              [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0
        else { throw QAError("a frame is x,y,width,height with a positive size, not \(part)") }
        return CGRect(x: x, y: y, width: width, height: height)
      }
      return (bundleID, frames)
    }
  }
#endif
