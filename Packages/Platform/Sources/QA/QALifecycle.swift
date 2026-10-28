#if DEBUG
  import AppKit
  import ComposableArchitecture
  import VortexCore

  /// How a QA run starts, says it is ready, relaunches and quits.
  @MainActor
  enum QALifecycle {
    /// The run's launch number: 1 the first time, one more after each relaunch.
    private(set) static var launch = 0
    /// The language the next relaunch starts with, once Settings changed it (simulated `setLanguage`).
    nonisolated static let nextLanguage = LockIsolated<AppLanguage?>(nil)

    static func bootstrap() {
      let qa = QALaunch.current
      qa.stopIfInvalid()
      guard let name = qa.name else { return }
      // No link may lead the run's folder into the user's.
      guard !QAPaths.isInside(QAPaths.resolved(DataFolder.url), QAPaths.resolved(QAPaths.userFolder)) else {
        stop("the QA folder \(DataFolder.url.path) leads into \(QAPaths.userFolder.path)")
      }
      do {
        try FileManager.default.createDirectory(at: QAPaths.controlFolder, withIntermediateDirectories: true)
      } catch {
        stop("the QA folder \(DataFolder.url.path) can't be made: \(error)")
      }
      launch = countLaunch()
      QASimulation.load()
      do {
        let port = try QAIsolation.seedServerPort(in: DataFolder.url)
        QALog.record("qa", "server port", ["port": "\(port)"])
      } catch {
        stop("the MCP port of the run can't be set: \(error)")
      }
      // Every system client is replaced before anything reads one; a client read earlier would stay live, so that
      // stops the run instead.
      let recorder = QAIssueRecorder(isGlobal: false)
      withIssueReporters([recorder]) {
        prepareDependencies { $0.useQAClients() }
      }
      if let issue = recorder.issues.value.first {
        stop("the system clients can't be replaced: \(issue)")
      }
      // From now on a call to something the simulation lacks shows as a violation.
      IssueReporters.current.append(QAIssueRecorder(isGlobal: true))
      QALog.record("qa", "launch", [
        "name": name,
        "launch": "\(launch)",
        "arguments": CommandLine.arguments.dropFirst().joined(separator: " "),
      ])
    }

    static func start() {
      guard let name = QA.name else { return }
      QAWindowGuard.install()
      QAListener.shared.start(channel: QA.channel(for: name))
      writeReadyMarker()
      NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification,
        object: nil,
        queue: .main
      ) { _ in
        MainActor.assumeIsolated { removeReadyMarker() }
      }
      QALog.record("qa", "listening", ["channel": QA.channel(for: name)])
    }

    /// The same build again, with the same arguments and the language Settings chose, through LaunchServices so it is
    /// a process of its own; this one quits once it has started. The new one takes over as one Vortex does from another.
    static func relaunchNow() {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.createsNewApplicationInstance = true
      configuration.activates = false
      configuration.addsToRecentItems = false
      configuration.arguments = relaunchArguments(Array(CommandLine.arguments.dropFirst()), language: nextLanguage.value)
      QALog.record("system", "relaunch", ["arguments": configuration.arguments.joined(separator: " ")])
      NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
        Task { @MainActor in
          if let error {
            QALog.violation("system", "relaunch failed", ["error": String(describing: error)])
          } else {
            NSApp.terminate(nil)
          }
        }
      }
    }

    /// The arguments for the next launch: these, with `-AppleLanguages` set to `language` when Settings chose one.
    static func relaunchArguments(_ arguments: [String], language: AppLanguage?) -> [String] {
      guard let language else { return arguments }
      var kept: [String] = []
      var index = arguments.startIndex
      while index < arguments.endIndex {
        if arguments[index] == "-AppleLanguages" {
          index += 2
          continue
        }
        kept.append(arguments[index])
        index += 1
      }
      return language == .system ? kept : kept + ["-AppleLanguages", "(\(language.rawValue))"]
    }

    /// The language the run was started with: `-AppleLanguages` among its arguments, or the system's.
    nonisolated static func launchLanguage() -> AppLanguage {
      let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
      guard let code = (arguments["AppleLanguages"] as? [String])?.first else { return .system }
      return AppLanguage.allCases.first { $0 != .system && code.hasPrefix($0.rawValue) } ?? .system
    }

    // MARK: - Files

    private static func countLaunch() -> Int {
      let previous = (try? String(contentsOf: QAPaths.launchesFile, encoding: .utf8))
        .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
      try? "\(previous + 1)\n".write(to: QAPaths.launchesFile, atomically: true, encoding: .utf8)
      return previous + 1
    }

    /// scripts/qa waits for this file, with this process's id, before it sends commands.
    private static func writeReadyMarker() {
      let marker: [String: Any] = ["pid": Int(getpid()), "launch": launch, "name": QA.name ?? ""]
      guard let data = try? JSONSerialization.data(withJSONObject: marker, options: [.sortedKeys]) else { return }
      try? data.write(to: QAPaths.readyFile, options: .atomic)
    }

    /// Only this process's marker: after a relaunch the new one may have written its own already.
    private static func removeReadyMarker() {
      guard let data = try? Data(contentsOf: QAPaths.readyFile),
            let marker = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            marker["pid"] as? Int == Int(getpid())
      else { return }
      try? FileManager.default.removeItem(at: QAPaths.readyFile)
    }

    private static func stop(_ reason: String) -> Never {
      FileHandle.standardError.write(Data("Vortex: QA run not started: \(reason)\n".utf8))
      exit(70)
    }
  }

  /// Issues the dependencies library reports: while the clients are replaced, any issue stops the run; afterwards each
  /// becomes a violation, such as a call to an endpoint the simulation doesn't have.
  final class QAIssueRecorder: IssueReporter {
    let isGlobal: Bool
    let issues = LockIsolated<[String]>([])

    init(isGlobal: Bool) {
      self.isGlobal = isGlobal
    }

    func reportIssue(
      _ message: @autoclosure () -> String?,
      severity: IssueSeverity,
      fileID: StaticString,
      filePath: StaticString,
      line: UInt,
      column: UInt
    ) {
      let text = message() ?? "an issue at \(fileID):\(line)"
      issues.withValue { $0.append(text) }
      if isGlobal {
        QALog.violation("issue", text, ["at": "\(fileID):\(line)"])
      }
    }
  }
#endif
