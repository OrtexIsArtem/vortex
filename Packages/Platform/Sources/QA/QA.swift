#if DEBUG
  import AppKit
  import ComposableArchitecture
  import VortexCore

  /// The answer to a command that went wrong: the reply says `"ok": false` with this message.
  public struct QAError: Error, CustomStringConvertible, Sendable {
    public let message: String

    public init(_ message: String) {
      self.message = message
    }

    public var description: String { message }
  }

  /// QA mode: a debug build started with `--qa <name>` runs as a copy of Vortex next to the user's own, which it never
  /// touches.
  ///
  /// - Its data folder is ~/Library/Application Support/Vortex QA/<name> (`DataFolder`).
  /// - Every system client with an effect outside that folder is simulated (`useQAClients`), and what they were asked
  ///   to do goes to the system events log.
  /// - Nothing shows: no menu bar icon, no ears, windows off the displays (`offscreen`), the app never in front.
  ///   A visible run (`isVisible`) shows its ears, notch window and flashes, to record a demo; the rest stays off.
  /// - It takes commands only on the distributed notification `io.github.ortexisartem.vortex.qa.<name>`, never the
  ///   `…debug.*` ones; `scripts/qa` sends them and waits for the reply.
  ///
  /// The shell, features and the onboarding add their own commands, state and windows here.
  public enum QA {
    /// Whether this process runs in QA mode. Safe from any thread.
    public static var isActive: Bool { name != nil }

    /// The run's name, from `--qa <name>`; nil outside QA mode.
    public static var name: String? { QALaunch.current.name }

    /// `--qa-release`: the run has the behaviors only release builds have, such as applying the login item.
    public static var releaseBehavior: Bool { QALaunch.current.options?.releaseBehavior == true }

    /// `--qa-visible`: the ears, the notch window and its flashes show on this Mac's displays as plain Vortex shows
    /// them, to record a demo. The run still takes no keyboard, pointer or front: commands stand for the user.
    public static var isVisible: Bool { QALaunch.current.options?.visible == true }

    /// The displays the run pretends to have, the main one first: `--qa-screens` at launch, otherwise this Mac's
    /// (a notch or not); the shell's `screens` command changes them. Empty outside QA mode.
    @MainActor
    public static var screens: [QALaunch.Screen] = QALaunch.current.options.map { options in
      options.screens ?? NSScreen.screens.map { $0.notchInPoints == nil ? .plain : .notch }
    } ?? []

    /// The size of the notch on a display the run pretends has one: this Mac's, or a MacBook Pro's.
    @MainActor
    public static var notchSize: CGSize {
      NSScreen.screens.lazy.compactMap(\.notchInPoints).first?.size ?? CGSize(width: 185, height: 32)
    }

    /// A command's handler gets its arguments: `key=value` as `key: value`, and a bare word as `word: ""`. It throws a
    /// `QAError` to answer with an error.
    public typealias Handler = @MainActor ([String: String]) async throws -> Void

    /// Adds a command, such as `onboarding press=next`; its reply says only whether it worked. Commands run one at a
    /// time, in the order they arrive.
    @MainActor
    public static func register(command: String, handler: @escaping Handler) {
      guard !QACommands.builtIn.contains(command) else {
        violation("qa", "a command named \(command) is built in")
        return
      }
      QARegistry.commands[command] = handler
    }

    /// Adds a section to the state dump, under `sections.<section>`: any value JSONEncoder can write.
    @MainActor
    public static func registerState(section: String, provider: @escaping @MainActor () -> any Encodable) {
      QARegistry.sections[section] = provider
    }

    /// Adds a window `snapshot window=<id>` can draw, and the state dump lists.
    @MainActor
    public static func registerWindow(id: String, provider: @escaping @MainActor () -> NSWindow?) {
      registerWindow(id: id, mode: { nil }, provider: provider)
    }

    /// The same, with the window's mode for the state dump, such as why the notch window is open.
    @MainActor
    public static func registerWindow(
      id: String,
      mode: @escaping @MainActor () -> String?,
      provider: @escaping @MainActor () -> NSWindow?
    ) {
      QARegistry.windows[id] = QARegistry.Window(provider: provider, mode: mode)
    }

    /// A frame of the same size that no display shows: every window of a QA run goes there. Below and left of all
    /// displays, so it never overlaps one however they are arranged.
    @MainActor
    public static func offscreen(_ frame: CGRect) -> CGRect {
      let displays = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
      let bounds = displays.isNull ? CGRect.zero : displays
      return CGRect(
        x: bounds.minX - frame.width - 2_000,
        y: bounds.minY - frame.height - 2_000,
        width: frame.width,
        height: frame.height
      )
    }

    /// Adds an entry to the system events log: what a simulated service was asked to do. Secrets are taken out.
    public static func log(_ client: String, _ event: String, _ detail: [String: String] = [:]) {
      QALog.record(client, event, detail)
    }

    /// Records something QA mode must never do, such as showing a window on a display.
    public static func violation(_ client: String, _ event: String, _ detail: [String: String] = [:]) {
      QALog.violation(client, event, detail)
    }

    /// Presses a shortcut, by its `Hotkey` name, for whoever listens; returns how many listen.
    @MainActor
    @discardableResult
    public static func pressHotkey(_ name: String) -> Int {
      QASystem.shared.pressHotkey(name)
    }

    /// Presses a key on the locked keyboard, as the lock sees it go down, for whoever listens; returns how many listen.
    @MainActor
    @discardableResult
    public static func pressKey(_ key: KeyboardKey) -> Int {
      QASystem.shared.pressKey(key)
    }

    /// Starts this build again with the same arguments, and quits; after the reply when a command asked for it.
    @MainActor
    public static func relaunch() {
      QACommands.afterReply { QALifecycle.relaunchNow() }
    }

    /// Quits; after the reply when a command asked for it.
    @MainActor
    public static func quit() {
      QACommands.afterReply { NSApp.terminate(nil) }
    }

    // MARK: - Lifecycle

    /// Call first in main.swift, before anything reads a dependency. Stops a process with a bad `--qa`; in QA mode
    /// prepares the run's folder and replaces the system clients. Does nothing otherwise.
    @MainActor
    public static func bootstrap() {
      QALifecycle.bootstrap()
    }

    /// Call when the shell starts, before it creates any window: from then on any window of the run that shows on a
    /// display is a violation, and is ordered out. Checks the windows already up. Does nothing outside QA mode.
    @MainActor
    public static func guardWindows() {
      guard isActive else { return }
      QAWindowGuard.install()
    }

    /// Call once the shell has put its window up and registered its commands: starts listening for commands and
    /// tells scripts/qa the run is ready.
    @MainActor
    public static func start() {
      QALifecycle.start()
    }

    /// Whether the app with this process id is the same kind of instance as this one: the same QA run, or both plain
    /// Vortex. A QA run never stops the user's Vortex or another run, and neither stops it.
    public static func isSameRun(pid: pid_t) -> Bool {
      guard let arguments = QAProcesses.arguments(of: pid) else { return !isActive }
      return isSameRun(arguments: arguments)
    }

    /// Whether a process started with `arguments` is the same kind of instance as one started as `launch`: the same
    /// run, its name compared in lowercase, or both plain Vortex.
    static func isSameRun(arguments: [String], as launch: QALaunch = .current) -> Bool {
      QALaunch(arguments: arguments).name == launch.name
    }

    /// Whether a window may become the key window. Never in a QA run: a panel made key takes the keys of the app the
    /// user types in, even while Vortex is not in front. Every window class of Vortex checks it in `canBecomeKey`.
    public static var allowsKeyWindows: Bool {
      allowsKeyWindows(for: .current)
    }

    /// Only plain Vortex: anything spelled like QA fails closed.
    static func allowsKeyWindows(for launch: QALaunch) -> Bool {
      launch == .none
    }

    /// Whether QA may touch the file at `path`: absolute, inside the run's folder or a temporary folder, and never in
    /// the user's data folder, with `..` and links resolved. Commands check the paths they are given with it.
    public static func isSafe(path: String) -> Bool {
      QAPaths.isSafe(path)
    }

    /// The distributed notification a run takes commands on.
    public static func channel(for name: String) -> String {
      "io.github.ortexisartem.vortex.qa.\(name)"
    }
  }

  /// What the shell, features and the onboarding registered.
  @MainActor
  enum QARegistry {
    struct Window {
      var provider: @MainActor () -> NSWindow?
      var mode: @MainActor () -> String?
    }

    static var commands: [String: QA.Handler] = [:]
    static var sections: [String: @MainActor () -> any Encodable] = [:]
    static var windows: [String: Window] = [:]
  }
#endif
