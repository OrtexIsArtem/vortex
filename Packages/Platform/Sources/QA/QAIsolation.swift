#if DEBUG
  import Foundation

  /// What keeps a QA run's services apart from the user's Vortex beyond the data folder.
  enum QAIsolation {
    /// The port of the user's Vortex MCP server, which a run must never take: two listeners may share a port, and
    /// Claude Code's requests would then reach the run.
    static let userPort = 47823
    /// The ephemeral range a run's port comes from.
    static let ports = 49152...65535

    /// Gives the run's MCP server a port of its own, from the ephemeral range, in the run's secrets.json, where the Keys
    /// feature reads it, before the feature starts. A port the run has already kept stays; the user's port, a missing
    /// one or an unreadable file get a new one. Returns the port.
    @discardableResult
    static func seedServerPort(in folder: URL, random: () -> Int = { Int.random(in: ports) }) throws -> Int {
      let file = folder.appending(path: "secrets.json")
      var settings = (try? Data(contentsOf: file))
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
      if let port = settings["port"] as? Int, port != userPort, ports.contains(port) {
        return port
      }
      let port = random()
      precondition(port != userPort && ports.contains(port))
      settings["port"] = port
      let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try data.write(to: file, options: .atomic)
      return port
    }
  }
#endif
