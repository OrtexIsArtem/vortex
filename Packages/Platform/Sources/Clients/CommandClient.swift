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

enum Spawn {
  static func run(
    _ command: String,
    in directory: URL?,
    environment extra: [String: String],
    timeout: Duration
  ) async throws -> CommandClient.Output {
    let shell = loginShell
    let output: CommandClient.Output
    if let terminal = await TerminalEnvironment.shared.value(shell: shell) {
      output = try await spawn([shell, "-c", command], in: directory, environment: terminal.merging(extra) { $1 }, timeout: timeout)
    } else {
      // The shell didn't say what a terminal gets: its login profile sets the PATH and the rest.
      output = try await spawn([shell, "-l", "-c", command], in: directory, environment: environment(shell: shell, adding: extra), timeout: timeout)
    }
    // A command not found may be a tool installed since: the next command asks the shell again.
    if output.exitCode == 127, !output.timedOut { await TerminalEnvironment.shared.forget() }
    return output
  }

  /// Runs `words` (the program, then its arguments) with exactly `environment`.
  static func spawn(
    _ words: [String],
    in directory: URL?,
    environment: [String: String],
    timeout: Duration
  ) async throws -> CommandClient.Output {
    let output = try PipeEnds()
    let errors: PipeEnds
    do {
      errors = try PipeEnds()
    } catch {
      close(output.read)
      close(output.write)
      throw error
    }

    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_adddup2(&actions, output.write, 1)
    posix_spawn_file_actions_adddup2(&actions, errors.write, 2)
    posix_spawn_file_actions_addchdir_np(&actions, (directory ?? FileManager.default.homeDirectoryForCurrentUser).path)

    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    // A process group of its own, to stop it with everything it starts; signals as a terminal's command gets them; no
    // other descriptor of Vortex's.
    let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
    posix_spawnattr_setflags(&attributes, Int16(flags))
    posix_spawnattr_setpgroup(&attributes, 0)
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
    close(output.write)
    close(errors.write)
    guard spawned == 0 else {
      close(output.read)
      close(errors.read)
      throw POSIXError(POSIXErrorCode(rawValue: spawned) ?? .EIO)
    }

    let timedOut = Flag()
    let group = pid
    let deadline = Task {
      try await Task.sleep(for: timeout)
      timedOut.set()
      killpg(group, SIGTERM)
      try await Task.sleep(for: .seconds(2))
      killpg(group, SIGKILL)
    }
    defer { deadline.cancel() }

    return await withTaskCancellationHandler {
      async let stdout = drain(output.read)
      async let stderr = drain(errors.read)
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
  static func environment(shell: String, adding extra: [String: String]) -> [String: String] {
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
    return environment.merging(extra) { $1 }
  }

  /// Everything written to `descriptor` until it closes, up to `CommandClient.outputLimit`; read on a thread of its
  /// own, as it blocks.
  static func drain(_ descriptor: Int32) async -> Data {
    await withCheckedContinuation { continuation in
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
/// interactive, so what `.zshrc` adds (nvm's node, `~/.local/bin`) is there too. Asked once, as that takes a moment;
/// again after a command wasn't found.
actor TerminalEnvironment {
  static let shared = TerminalEnvironment()
  private static let marker = "__VORTEX_ENVIRONMENT__"

  private var answer: Task<[String: String]?, Never>?

  /// Nil when the shell doesn't answer in time; then it isn't asked again until `forget()`.
  func value(shell: String) async -> [String: String]? {
    if let answer { return await answer.value }
    let task = Task { await Self.ask(shell: shell, base: Spawn.environment(shell: shell, adding: [:])) }
    answer = task
    return await task.value
  }

  func forget() {
    answer = nil
  }

  /// What `shell`, started with `base` the way a terminal starts it, exports; whatever its startup files print is
  /// skipped. Nil when it fails or takes longer than `timeout`.
  static func ask(shell: String, base: [String: String], timeout: Duration = .seconds(10)) async -> [String: String]? {
    let words = [shell, "-l", "-i", "-c", "/usr/bin/printf %s \(marker); /usr/bin/env -0"]
    guard let output = try? await Spawn.spawn(words, in: nil, environment: base, timeout: timeout),
          !output.timedOut, output.exitCode == 0,
          let start = output.stdout.range(of: Data(marker.utf8))?.upperBound
    else { return nil }
    var environment: [String: String] = [:]
    for entry in output.stdout[start...].split(separator: 0) {
      let text = String(decoding: entry, as: UTF8.self)
      guard let equals = text.firstIndex(of: "=") else { continue }
      environment[String(text[..<equals])] = String(text[text.index(after: equals)...])
    }
    // The shell's own bookkeeping; the command's shell sets these itself.
    for name in ["PWD", "OLDPWD", "SHLVL", "_"] { environment[name] = nil }
    // No colors, no pagers.
    environment["TERM"] = "dumb"
    return environment["PATH"] == nil ? nil : environment
  }
}

private struct PipeEnds {
  let read: Int32
  let write: Int32

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
