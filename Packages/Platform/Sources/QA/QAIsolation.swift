#if DEBUG
  import Foundation

  /// What keeps a QA run's services apart from the user's Vortex beyond the data folder.
  enum QAIsolation {
    /// Items inside the run's folder through which writes would land elsewhere, such as the user's database: links
    /// that lead out of the folder, and files with a second name (a hard link) anywhere. The run must not start with any.
    static func itemsLeadingOut(of folder: URL) -> [String] {
      let root = QAPaths.resolved(folder)
      let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .linkCountKey]
      guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return [] }
      var leading: [String] = []
      for case let item as URL in items {
        guard let values = try? item.resourceValues(forKeys: Set(keys)) else { continue }
        if values.isSymbolicLink == true {
          // Where the link points, even when nothing is there yet: SQLite would create the file through it.
          let destination = (try? FileManager.default.destinationOfSymbolicLink(atPath: item.path)) ?? "/"
          let target = destination.hasPrefix("/") ? destination : item.deletingLastPathComponent().path + "/" + destination
          if !QAPaths.isInside(QAPaths.resolved(URL(fileURLWithPath: target)), root) { leading.append(item.path) }
        } else if values.isRegularFile == true, (values.linkCount ?? 1) > 1 {
          leading.append(item.path)
        }
      }
      return leading
    }

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
