import Darwin

/// Leaves a mark as Vortex crashes, so the next launch can tell a crash from a kill: Xcode's Stop, Force Quit and a
/// second copy taking over end Vortex with SIGKILL or SIGTERM, which no handler sees, and leave no mark.
enum CrashSignals {
  static let signals = [SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE]

  /// Opens the marker now, as a crashing process can do almost nothing, and handles each crash signal: the handler
  /// writes one byte, then lets the signal end Vortex as before, so macOS still writes its crash report. Call once.
  static func install(markerPath: String) {
    crashMarker = open(markerPath, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0o644)
    guard crashMarker >= 0 else { return }
    // Called on the main thread, where every call into a feature runs: the mark tells a crash there from one elsewhere.
    mainThread = pthread_self()
    // A stack overflow on the main thread leaves no stack for the handler; it runs on one of its own.
    let size = 64 * 1024
    var stack = stack_t(ss_sp: UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16), ss_size: size, ss_flags: 0)
    sigaltstack(&stack, nil)
    for number in signals {
      var action = sigaction()
      action.__sigaction_u.__sa_handler = markCrash
      sigemptyset(&action.sa_mask)
      action.sa_flags = SA_ONSTACK
      sigaction(number, &action, nil)
    }
  }
}

/// The marker's file descriptor, opened before any crash.
nonisolated(unsafe) private var crashMarker: Int32 = -1
/// The thread that installed the handler: the main thread.
nonisolated(unsafe) private var mainThread: pthread_t?

/// Async-signal-safe only: which thread this is, a write, then the default action again for the same signal. The byte
/// is 1 on the main thread and 2 on any other.
private func markCrash(_ number: Int32) {
  var mark: UInt8 = mainThread.map { pthread_equal(pthread_self(), $0) != 0 } == true ? 1 : 2
  _ = write(crashMarker, &mark, 1)
  signal(number, SIG_DFL)
  raise(number)
}
