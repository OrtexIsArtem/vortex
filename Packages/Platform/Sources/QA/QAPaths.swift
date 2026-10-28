#if DEBUG
  import Foundation
  import VortexCore

  /// Where a QA run keeps its files, and where it may write.
  enum QAPaths {
    /// The user's own data folder, which a QA run never touches: ~/Library/Application Support/Vortex.
    static let userFolder = URL.applicationSupportDirectory.appending(path: "Vortex", directoryHint: .isDirectory)

    /// QA's own files inside the run's data folder: the ready marker, the simulation, replies of scripts/qa.
    static var controlFolder: URL { DataFolder.url.appending(path: ".qa", directoryHint: .isDirectory) }
    /// Written once the run listens for commands: its pid and launch number. Gone when it quits.
    static var readyFile: URL { controlFolder.appending(path: "ready.json") }
    /// What the simulated system services answer, see `QASimulation`.
    static var simulationFile: URL { controlFolder.appending(path: "simulation.json") }
    /// How many times the run has started.
    static var launchesFile: URL { controlFolder.appending(path: "launches") }
    /// Files a tester puts in for the simulated services: screen.png, the display a capture sees.
    static var fixturesFolder: URL { DataFolder.url.appending(path: "fixtures", directoryHint: .isDirectory) }

    /// Where a QA run may write and read: its own data folder and the temporary folders.
    static var allowedFolders: [URL] {
      [DataFolder.url, FileManager.default.temporaryDirectory, URL(fileURLWithPath: "/tmp", isDirectory: true)]
    }

    /// Whether QA may touch the file at `path`: an absolute path inside its own data folder or a temporary folder, and
    /// never inside the user's data folder.
    static func isSafe(_ path: String) -> Bool {
      path.hasPrefix("/") && isSafe(URL(fileURLWithPath: path), allowed: allowedFolders, forbidden: [userFolder])
    }

    static func isSafe(_ url: URL) -> Bool {
      url.isFileURL && isSafe(url.path)
    }

    /// Whether `url` lies inside one of `allowed` and inside none of `forbidden`, once `.`, `..` and symbolic links
    /// are resolved. Folders compare by whole components and ignore case, as the Mac's disks do.
    static func isSafe(_ url: URL, allowed: [URL], forbidden: [URL]) -> Bool {
      let path = resolved(url)
      return allowed.contains { isInside(path, resolved($0)) } && !forbidden.contains { isInside(path, resolved($0)) }
    }

    /// Whether `path` is `folder` itself or lies below it.
    static func isInside(_ path: [String], _ folder: [String]) -> Bool {
      path.count >= folder.count
        && zip(path, folder).allSatisfy { $0.lowercased() == $1.lowercased() }
    }

    /// The components of an absolute path, without the leading "/", as the file system sees it: the longest part that
    /// exists goes through `realpath` (links, `..`), and the rest, which can hold no links, is resolved by name.
    static func resolved(_ url: URL) -> [String] {
      let parts = url.path.split(separator: "/").map(String.init)
      var existing = parts.count
      var base: [String]?
      while base == nil, existing >= 0 {
        if let real = realpath("/" + parts.prefix(existing).joined(separator: "/"), nil) {
          base = String(cString: real).split(separator: "/").map(String.init)
          free(real)
        } else {
          existing -= 1
        }
      }
      var components = base ?? []
      for part in parts.dropFirst(max(existing, 0)) {
        switch part {
        case ".":
          continue
        case "..":
          if !components.isEmpty { components.removeLast() }
        default:
          components.append(part)
        }
      }
      return components
    }
  }
#endif
