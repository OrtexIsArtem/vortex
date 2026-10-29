#if DEBUG
  import Darwin
  import Foundation

  /// The launch arguments of another process of this user, to tell a QA run from plain Vortex.
  enum QAProcesses {
    /// Its arguments, the executable first; nil when the system doesn't say.
    static func arguments(of pid: pid_t) -> [String]? {
      var request: [Int32] = [CTL_KERN, KERN_ARGMAX]
      var argumentMax: Int32 = 0
      var size = MemoryLayout<Int32>.size
      guard sysctl(&request, 2, &argumentMax, &size, nil, 0) == 0, argumentMax > 0 else { return nil }
      var buffer = [UInt8](repeating: 0, count: Int(argumentMax))
      var length = buffer.count
      request = [CTL_KERN, KERN_PROCARGS2, pid]
      guard sysctl(&request, 3, &buffer, &length, nil, 0) == 0 else { return nil }
      return arguments(fromProcessArguments: Array(buffer.prefix(length)))
    }

    /// Reads KERN_PROCARGS2: the argument count (a 32-bit integer), the executable path, padding zeros, then the
    /// arguments, each ending in a zero, then the environment. Nil when it is cut short.
    static func arguments(fromProcessArguments buffer: [UInt8]) -> [String]? {
      guard buffer.count >= 4 else { return nil }
      let count = buffer.prefix(4).enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
      var index = 4
      while index < buffer.count, buffer[index] != 0 { index += 1 }
      while index < buffer.count, buffer[index] == 0 { index += 1 }
      var arguments: [String] = []
      while arguments.count < count, index < buffer.count {
        let start = index
        while index < buffer.count, buffer[index] != 0 { index += 1 }
        guard index < buffer.count else { return nil }
        arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
        index += 1
      }
      return arguments.count == count ? arguments : nil
    }
  }
#endif
