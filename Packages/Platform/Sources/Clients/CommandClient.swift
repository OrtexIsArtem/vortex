import ComposableArchitecture
import Darwin
import Foundation

/// Commands run in the user's shell as their terminal runs them: with the environment a terminal window gets, `.zshrc`
/// included.
@DependencyClient
public struct CommandClient: Sendable {
  public struct Output: Equatable, Sendable {
    public var exitCode: Int32
    public var stdout: Data
    public var stderr: Data
    /// Stopped because its time was up; `exitCode` is then the signal's.
    public var timedOut: Bool

    /// The shell couldn't find a command it was told to run.
    public var isCommandNotFound: Bool { exitCode == 127 && !timedOut }

    public init(exitCode: Int32, stdout: Data = Data(), stderr: Data = Data(), timedOut: Bool = false) {
      self.exitCode = exitCode
      self.stdout = stdout
      self.stderr = stderr
      self.timedOut = timedOut
    }
  }

  /// How much of each output is kept; the rest is read and dropped.
  public static let outputLimit = 1 << 20

  /// Runs `command` in `directory` (the home folder when nil) with `environment` added. It gets no input and none of
  /// Vortex's own environment, and once `timeout` is up, or the task is cancelled, it is stopped with everything it
  /// started; so is whatever it left running when it ends.
  public var run: @Sendable (
    _ command: String,
    _ directory: URL?,
    _ environment: [String: String],
    _ timeout: Duration
  ) async throws -> Output
}

extension CommandClient: DependencyKey {
  public static let liveValue = CommandClient(
    run: { command, directory, environment, timeout in
      try await Spawn.run(command, in: directory, environment: environment, timeout: timeout)
    }
  )

  public static let testValue = CommandClient()
}

extension DependencyValues {
  public var commandClient: CommandClient {
    get { self[CommandClient.self] }
    set { self[CommandClient.self] = newValue }
  }
}

private enum Spawn {
  static func run(
    _ command: String,
    in directory: URL?,
    environment extra: [String: String],
    timeout: Duration
  ) async throws -> CommandClient.Output {
    let shell = loginShell
    let terminal = await TerminalEnvironment.shared.value(shell: shell)
    // Asking the shell takes a moment; a call given up meanwhile starts nothing.
    try Task.checkCancellation()
    // With what a terminal gets, the command needs nothing more; without it, the login profile sets the PATH and the
    // rest.
    let (flags, base) = terminal.map { (["-c"], $0) } ?? (["-l", "-c"], environment(shell: shell))
    let output = try await spawn([shell] + flags + [command], in: directory, environment: base.merging(extra) { $1 }, timeout: timeout)
    if output.isCommandNotFound { await TerminalEnvironment.shared.commandNotFound() }
    return output
  }

  /// Runs `words` (the program, then its arguments) with exactly `environment`. With `capturing` false what it prints
  /// goes nowhere, so nothing it leaves running can keep this waiting for the end of its output.
  static func spawn(
    _ words: [String],
    in directory: URL?,
    environment: [String: String],
    timeout: Duration,
    capturing: Bool = true
  ) async throws -> CommandClient.Output {
    let output = capturing ? try PipeEnds() : nil
    let errors: PipeEnds?
    do {
      errors = capturing ? try PipeEnds() : nil
    } catch {
      output?.closeBoth()
      throw error
    }

    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    if let output, let errors {
      posix_spawn_file_actions_adddup2(&actions, output.write, 1)
      posix_spawn_file_actions_adddup2(&actions, errors.write, 2)
    } else {
      posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
      posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
    }
    posix_spawn_file_actions_addchdir_np(&actions, (directory ?? FileManager.default.homeDirectoryForCurrentUser).path)

    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    // A session of its own, without a terminal: its process group stops it with everything it starts, and an
    // interactive shell never waits for a terminal Vortex was started from. Signals as a terminal's command gets them;
    // no other descriptor of Vortex's.
    let flags = POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
    posix_spawnattr_setflags(&attributes, Int16(flags))
    var defaults = sigset_t()
    sigfillset(&defaults)
    sigdelset(&defaults, SIGKILL)
    sigdelset(&defaults, SIGSTOP)
    posix_spawnattr_setsigdefault(&attributes, &defaults)
    var mask = sigset_t()
    sigemptyset(&mask)
    posix_spawnattr_setsigmask(&attributes, &mask)

    let arguments: [UnsafeMutablePointer<CChar>?] = words.map { strdup($0) } + [nil]
    let pairs = environment.map { "\($0.key)=\($0.value)" }
    let variables: [UnsafeMutablePointer<CChar>?] = pairs.map { strdup($0) } + [nil]
    defer { (arguments + variables).forEach { free($0) } }

    var pid: pid_t = 0
    let spawned = posix_spawn(&pid, words[0], &actions, &attributes, arguments, variables)
    for pipe in [output, errors].compactMap(\.self) { close(pipe.write) }
    guard spawned == 0 else {
      for pipe in [output, errors].compactMap(\.self) { close(pipe.read) }
      throw POSIXError(POSIXErrorCode(rawValue: spawned) ?? .EIO)
    }

    let timedOut = Flag()
    let group = pid
    RunningGroups.shared.insert(group)
    defer { RunningGroups.shared.remove(group) }
    let deadline = Task {
      try await Task.sleep(for: timeout)
      timedOut.set()
      killpg(group, SIGTERM)
      try await Task.sleep(for: .seconds(2))
      killpg(group, SIGKILL)
    }
    defer { deadline.cancel() }

    return await withTaskCancellationHandler {
      async let stdout = drain(output?.read)
      async let stderr = drain(errors?.read)
      let status = await exitStatus(of: pid)
      // What it left running would hold the outputs open.
      killpg(group, SIGKILL)
      let exited = status & 0x7F == 0
      return CommandClient.Output(
        exitCode: exited ? (status >> 8) & 0xFF : 128 + status & 0x7F,
        stdout: await stdout,
        stderr: await stderr,
        timedOut: timedOut.isSet
      )
    } onCancel: {
      killpg(group, SIGKILL)
    }
  }

  /// The user's login shell; zsh when it can't be read.
  static var loginShell: String {
    if let entry = getpwuid(getuid()), let path = entry.pointee.pw_shell.map({ String(cString: $0) }),
       FileManager.default.isExecutableFile(atPath: path) {
      return path
    }
    return "/bin/zsh"
  }

  /// Only what a login shell starts from: its profile sets the PATH and the rest.
  static func environment(shell: String) -> [String: String] {
    let own = ProcessInfo.processInfo.environment
    var environment: [String: String] = [
      "HOME": own["HOME"] ?? NSHomeDirectory(),
      "SHELL": shell,
      "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
      "LANG": own["LANG"] ?? "en_US.UTF-8",
      // No colors, no pagers.
      "TERM": "dumb",
    ]
    for name in ["USER", "LOGNAME", "TMPDIR", "SSH_AUTH_SOCK", "__CF_USER_TEXT_ENCODING"] {
      environment[name] = own[name]
    }
    return environment
  }

  /// Everything written to `descriptor` until it closes, up to `CommandClient.outputLimit`; read on a thread of its
  /// own, as it blocks. Nothing without one.
  static func drain(_ descriptor: Int32?) async -> Data {
    guard let descriptor else { return Data() }
    return await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
          let count = read(descriptor, &buffer, buffer.count)
          if count < 0, errno == EINTR { continue }
          guard count > 0 else { break }
          let room = CommandClient.outputLimit - data.count
          if room > 0 { data.append(contentsOf: buffer[0..<min(count, room)]) }
        }
        close(descriptor)
        continuation.resume(returning: data)
      }
    }
  }

  /// The status `waitpid` gives once the process ends; waited for on a thread of its own, as it blocks.
  static func exitStatus(of pid: pid_t) async -> Int32 {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0, errno == EINTR {}
        continuation.resume(returning: status)
      }
    }
  }
}

/// The environment the user's terminal gives a command: their shell started as a terminal window starts it, login and
/// interactive, so what `.zshrc` exports (nvm's node, `~/.local/bin`) is there too; aliases, functions and options are
/// not. Asked once, as that takes a moment; again once a startup file changes, after `freshness`, or after a command
/// wasn't found.
actor TerminalEnvironment {
  static let shared = TerminalEnvironment()
  /// How long an answer serves, for what no file date shows: files `.zshrc` sources, values worked out as it starts.
  static let freshness: TimeInterval = 600

  private var answer: Task<[String: String]?, Never>?
  private var askedShell: String?
  private var askedAt = Date.distantPast
  private var stamp: [String: Date] = [:]
  /// Where the last answer said zsh keeps its startup files, when not in the home folder.
  private var zdotdir: String?

  /// Nil when the shell doesn't answer in time; then it isn't asked again until a startup file changes or a while has
  /// passed.
  func value(shell: String) async -> [String: String]? {
    let current = Self.stamp(zdotdir: zdotdir)
    if let answer, shell == askedShell, current == stamp, Date.now.timeIntervalSince(askedAt) < Self.freshness {
      return await answer.value
    }
    let task = Task { await Self.ask(shell: shell, base: Spawn.environment(shell: shell)) }
    answer = task
    askedShell = shell
    askedAt = .now
    stamp = current
    let value = await task.value
    if answer == task, let found = value?["ZDOTDIR"], found != zdotdir {
      zdotdir = found
      stamp = Self.stamp(zdotdir: found)
    }
    return value
  }

  /// A command wasn't found, maybe a tool installed since: the next command asks the shell again. Not when it was asked
  /// a moment ago, or didn't answer in time, which would only make every command wait for it again.
  func commandNotFound() async {
    guard let answer, Date.now.timeIntervalSince(askedAt) > 30, await answer.value != nil else { return }
    if self.answer == answer { self.answer = nil }
  }

  /// The dates of the files a shell reads as it starts, by path: a link's own and its file's, so an edit through a link
  /// (dotfile managers) shows, and so does a file that appears or goes.
  static func stamp(home: URL = FileManager.default.homeDirectoryForCurrentUser, zdotdir: String?) -> [String: Date] {
    var folders = [home]
    if let zdotdir, !zdotdir.isEmpty { folders.append(URL(fileURLWithPath: zdotdir, isDirectory: true)) }
    let names = [".zshenv", ".zprofile", ".zshrc", ".zlogin", ".bash_profile", ".bashrc", ".profile", ".config/fish/config.fish"]
    var dates: [String: Date] = [:]
    for file in folders.flatMap({ folder in names.map { folder.appending(path: $0) } }) {
      for url in Set([file, file.resolvingSymlinksInPath()]) {
        if let date = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date {
          dates[url.path] = date
        }
      }
    }
    return dates
  }

  /// What `shell`, started with `base` the way a terminal starts it, exports. It writes that to a file and prints
  /// nowhere, so what its startup files print or leave running doesn't matter. Nil when it fails or takes longer than
  /// `timeout`.
  static func ask(shell: String, base: [String: String], timeout: Duration = .seconds(10)) async -> [String: String]? {
    let file = FileManager.default.temporaryDirectory.appending(path: "vortex-environment-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: file) }
    var environment = base
    // A terminal's: startup files often stop early for a dumb one, before nvm and the rest.
    environment["TERM"] = "xterm-256color"
    let words = [shell, "-l", "-i", "-c", "/usr/bin/env -0 > '\(file.path)'"]
    guard let output = try? await Spawn.spawn(words, in: nil, environment: environment, timeout: timeout, capturing: false),
          !output.timedOut, output.exitCode == 0,
          let data = try? Data(contentsOf: file)
    else { return nil }
    var answer: [String: String] = [:]
    for entry in data.split(separator: 0) {
      let text = String(decoding: entry, as: UTF8.self)
      guard let equals = text.firstIndex(of: "=") else { continue }
      answer[String(text[..<equals])] = String(text[text.index(after: equals)...])
    }
    // The shell's own bookkeeping; the command's shell sets these itself.
    for name in ["PWD", "OLDPWD", "SHLVL", "_"] { answer[name] = nil }
    // No colors, no pagers.
    answer["TERM"] = "dumb"
    return answer["PATH"] == nil ? nil : answer
  }
}

/// The process groups of the commands running now, stopped when Vortex exits: in sessions of their own, they would go on
/// without the time limit Vortex keeps.
private final class RunningGroups: @unchecked Sendable {
  static let shared = RunningGroups()
  private let lock = NSLock()
  private var groups: Set<pid_t> = []

  private init() {
    atexit { RunningGroups.shared.stopAll() }
  }

  func insert(_ group: pid_t) {
    _ = lock.withLock { groups.insert(group) }
  }

  func remove(_ group: pid_t) {
    _ = lock.withLock { groups.remove(group) }
  }

  private func stopAll() {
    for group in lock.withLock({ groups }) { killpg(group, SIGKILL) }
  }
}

private struct PipeEnds {
  let read: Int32
  let write: Int32

  func closeBoth() {
    close(read)
    close(write)
  }

  init() throws {
    var descriptors: [Int32] = [0, 0]
    guard pipe(&descriptors) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    read = descriptors[0]
    write = descriptors[1]
  }
}

/// Set once, from any thread.
private final class Flag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  var isSet: Bool { lock.withLock { value } }

  func set() {
    lock.withLock { value = true }
  }
}
