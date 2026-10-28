#if DEBUG
  import AppKit
  import ComposableArchitecture
  import VortexCore

  /// A command as it arrives on the run's channel.
  struct QACommand: Equatable, Sendable {
    var name: String
    /// `key=value` as `key: value`; a bare word as `word: ""`.
    var arguments: [String: String]
    /// The file the reply goes to; without one there is no reply.
    var reply: String?

    /// From a notification's userInfo: `command` names it, `reply` is where the reply goes, every other entry is an
    /// argument. Nil without a command.
    init?(userInfo: [String: String]) {
      guard let name = userInfo["command"]?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
      self.name = name
      reply = userInfo["reply"].flatMap { $0.isEmpty ? nil : $0 }
      var arguments = userInfo
      arguments["command"] = nil
      arguments["reply"] = nil
      self.arguments = arguments
    }

    /// The string entries of a notification's userInfo; anything else is left out.
    static func strings(_ userInfo: [AnyHashable: Any]?) -> [String: String] {
      var strings: [String: String] = [:]
      for (key, value) in userInfo ?? [:] {
        guard let key = key as? String, let value = value as? String else { continue }
        strings[key] = value
      }
      return strings
    }
  }

  /// Takes commands from the run's channel, in the order they come.
  @MainActor
  final class QAListener: NSObject {
    static let shared = QAListener()
    private var queue: AsyncStream<QACommand>.Continuation?

    func start(channel: String) {
      guard queue == nil else { return }
      let (stream, continuation) = AsyncStream.makeStream(of: QACommand.self)
      queue = continuation
      // Delivered also while Vortex is not the app in front, which a QA run never is.
      DistributedNotificationCenter.default().addObserver(
        self,
        selector: #selector(received(_:)),
        name: Notification.Name(channel),
        object: nil,
        suspensionBehavior: .deliverImmediately
      )
      Task { @MainActor in
        for await command in stream {
          await QACommands.run(command)
        }
      }
    }

    @objc nonisolated private func received(_ notification: Notification) {
      let info = QACommand.strings(notification.userInfo)
      let deliver: @MainActor () -> Void = { QAListener.shared.enqueue(info) }
      if Thread.isMainThread {
        MainActor.assumeIsolated(deliver)
      } else {
        Task { @MainActor in deliver() }
      }
    }

    private func enqueue(_ info: [String: String]) {
      guard let command = QACommand(userInfo: info) else {
        QALog.violation("qa", "a notification without a command", info)
        return
      }
      queue?.yield(command)
    }
  }

  /// Runs commands one at a time and writes each reply: `{"ok": true, "command": …, "pid": …, "result": …}`, or
  /// `"ok": false` with `"error"`.
  @MainActor
  enum QACommands {
    static let builtIn: Set<String> = ["app", "help", "quit", "relaunch", "sim", "snapshot", "state"]
    private static var isRunning = false
    private static var pending: [@MainActor () -> Void] = []

    /// Runs `action` once the command running now has its reply written, or at once when none runs: a quit or a
    /// relaunch must not lose the reply of the command that caused it.
    static func afterReply(_ action: @escaping @MainActor () -> Void) {
      if isRunning {
        pending.append(action)
      } else {
        action()
      }
    }

    static func run(_ command: QACommand) async {
      isRunning = true
      var reply: [String: Any] = ["command": command.name, "pid": Int(getpid())]
      do {
        if let result = try await execute(command) {
          reply["result"] = result
        }
        reply["ok"] = true
      } catch {
        reply["ok"] = false
        reply["error"] = String(describing: error)
      }
      var detail = command.arguments
      detail["command"] = command.name
      detail["ok"] = "\(reply["ok"] as? Bool ?? false)"
      QALog.record("qa", "command", detail)
      write(reply, to: command.reply)
      isRunning = false
      let actions = pending
      pending = []
      actions.forEach { $0() }
    }

    private static func execute(_ command: QACommand) async throws -> Any? {
      let arguments = command.arguments
      switch command.name {
      case "state":
        return try state(arguments)
      case "snapshot":
        return try snapshot(arguments)
      case "relaunch":
        QA.relaunch()
        return ["relaunching": true]
      case "quit":
        QA.quit()
        return ["quitting": true]
      case "help":
        return help()
      case "sim":
        return try QASystem.shared.simulate(arguments)
      case "app":
        try QASystem.shared.app(arguments)
        return nil
      default:
        guard let handler = QARegistry.commands[command.name] else {
          throw QAError("unknown command \(command.name); there are \(names.joined(separator: ", "))")
        }
        try await handler(arguments)
        return nil
      }
    }

    private static var names: [String] {
      (builtIn.union(QARegistry.commands.keys)).sorted()
    }

    // MARK: - Built-in commands

    /// `state [path=<file>]`: the dump goes to the file, or into the reply.
    private static func state(_ arguments: [String: String]) throws -> Any? {
      let dump = QAState.dump()
      guard let path = arguments["path"] else { return dump }
      try writeJSON(dump, to: path)
      return ["path": path]
    }

    /// `snapshot window=<id> path=<file.png>`: the window as the app draws it.
    private static func snapshot(_ arguments: [String: String]) throws -> Any? {
      let ids = QARegistry.windows.keys.sorted().joined(separator: ", ")
      guard let id = arguments["window"], let entry = QARegistry.windows[id] else {
        throw QAError("snapshot needs window=<id>, one of \(ids)")
      }
      guard let path = arguments["path"] else { throw QAError("snapshot needs path=<file.png>") }
      guard QAPaths.isSafe(path) else { throw QAError("files go inside the QA folder or a temporary folder, not \(path)") }
      guard let window = entry.provider() else { throw QAError("the \(id) window does not exist now") }
      let image = try QASnapshot.png(of: window)
      try write(image.data, to: path)
      return [
        "path": path,
        "width": image.size.width,
        "height": image.size.height,
        "scale": image.scale,
        "visible": window.isVisible,
      ]
    }

    private static func help() -> Any {
      [
        "commands": names,
        "sections": QARegistry.sections.keys.sorted(),
        "windows": QARegistry.windows.keys.sorted(),
      ]
    }

    // MARK: - Files

    private static func write(_ reply: [String: Any], to path: String?) {
      guard let path else { return }
      do {
        try writeJSON(reply, to: path)
      } catch {
        QALog.violation("qa", "a reply was not written", ["path": path, "error": String(describing: error)])
      }
    }

    private static func writeJSON(_ object: Any, to path: String) throws {
      guard JSONSerialization.isValidJSONObject(object) else { throw QAError("the answer is not JSON") }
      let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
      try write(data, to: path)
    }

    /// Only inside the QA folder or a temporary folder, never the user's data; atomically, so a reader never sees half.
    private static func write(_ data: Data, to path: String) throws {
      guard QAPaths.isSafe(path) else { throw QAError("files go inside the QA folder or a temporary folder, not \(path)") }
      let url = URL(fileURLWithPath: path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
    }
  }

  /// The state dump: the run, the simulation, windows, notch indicators, the system events log, violations and the
  /// sections the shell and features registered.
  @MainActor
  enum QAState {
    static func dump() -> [String: Any] {
      var sections: [String: Any] = [:]
      for (name, provider) in QARegistry.sections {
        sections[name] = json(provider())
      }
      return [
        "qa": [
          "name": QA.name ?? "",
          "pid": Int(getpid()),
          "launch": QALifecycle.launch,
          "arguments": Array(CommandLine.arguments.dropFirst()),
          "dataFolder": DataFolder.url.path,
          "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
          "bundlePath": Bundle.main.bundlePath,
          "isActive": NSApp.isActive,
        ],
        "simulation": json(QASimulation.current.value),
        "windows": windows(),
        "notchIndicators": indicators(),
        "events": json(QALog.events.value),
        "violations": json(QALog.violations.value),
        "pasteboard": QASystem.shared.pasteboardDump(),
        "hotkeys": QASystem.shared.hotkeyNames(),
        "sections": sections,
      ]
    }

    /// A value as JSONSerialization takes it; the error when JSONEncoder can't write it.
    static func json(_ value: any Encodable) -> Any {
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      do {
        return try JSONSerialization.jsonObject(with: encoder.encode(value), options: [.fragmentsAllowed])
      } catch {
        return ["error": String(describing: error)]
      }
    }

    /// Registered windows, open or not, then any other window of the app that is up.
    static func windows() -> [[String: Any]] {
      var listed: [[String: Any]] = []
      var seen = Set<ObjectIdentifier>()
      for (id, entry) in QARegistry.windows.sorted(by: { $0.key < $1.key }) {
        guard let window = entry.provider() else {
          listed.append(["id": id, "exists": false])
          continue
        }
        seen.insert(ObjectIdentifier(window))
        listed.append(describe(window, id: id, mode: entry.mode()))
      }
      for window in NSApp.windows where window.isVisible && !seen.contains(ObjectIdentifier(window)) {
        listed.append(describe(window, id: nil, mode: nil))
      }
      return listed
    }

    private static func describe(_ window: NSWindow, id: String?, mode: String?) -> [String: Any] {
      let frame = window.frame
      var entry: [String: Any] = [
        "class": String(describing: type(of: window)),
        "frame": ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height],
        "visible": window.isVisible,
        "onDisplay": QAWindowGuard.isOnDisplay(window),
        "key": window.isKeyWindow,
        "level": window.level.rawValue,
      ]
      if let id { entry["id"] = id }
      if let mode { entry["mode"] = mode }
      if !window.title.isEmpty { entry["title"] = window.title }
      return entry
    }

    private static func indicators() -> [String: Any] {
      @Shared(.notchIndicators) var indicators
      let ears = NotchEars(indicators: indicators)
      var byFeature: [String: Any] = [:]
      for (id, indicator) in indicators {
        byFeature[id] = [
          "leading": indicator.leading.map(describe),
          "trailing": indicator.trailing.map(describe),
          "priority": indicator.priority,
          "flash": indicator.flash,
          "flashColor": hex(indicator.flashColor),
          "alarm": indicator.alarm.map { $0 as Any } ?? NSNull(),
        ]
      }
      return [
        "byFeature": byFeature,
        "ears": ["left": ears.leftFeature ?? NSNull(), "right": ears.rightFeature ?? NSNull()] as [String: Any],
      ]
    }

    private static func describe(_ item: NotchIndicator.Item) -> String {
      switch item {
      case let .symbol(name): "symbol:\(name)"
      case let .text(text): "text:\(text)"
      case let .progress(value): "progress:\((value * 100).rounded() / 100)"
      }
    }

    private static func hex(_ color: ColorValue) -> String {
      func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
      return String(format: "#%02X%02X%02X", byte(color.red), byte(color.green), byte(color.blue))
    }
  }
#endif
