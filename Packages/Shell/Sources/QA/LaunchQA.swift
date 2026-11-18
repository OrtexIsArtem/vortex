#if DEBUG
  import Foundation
  import VortexCore
  import VortexPlatform

  /// QA's `launch set=normal|safe|stop:<id>`: the verdict the next launch of the run takes instead of its own, to show
  /// safe mode or a stopped feature without crashing. Kept in the run's own folder until that launch reads it.
  enum LaunchQA {
    static var nextVerdictFile: URL {
      DataFolder.url.appending(path: ".qa", directoryHint: .isDirectory).appending(path: "next-launch")
    }

    static func setNextVerdict(_ word: String) throws {
      _ = try LaunchVerdict(qaWord: word)
      try FileManager.default.createDirectory(at: nextVerdictFile.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(word.utf8).write(to: nextVerdictFile, options: .atomic)
    }

    /// The verdict a command left for this launch, read once; nil outside QA mode or when none waits.
    static func takeNextVerdict() -> LaunchVerdict? {
      guard QA.isActive, let data = try? Data(contentsOf: nextVerdictFile) else { return nil }
      try? FileManager.default.removeItem(at: nextVerdictFile)
      return try? LaunchVerdict(qaWord: String(decoding: data, as: UTF8.self))
    }
  }

  extension LaunchVerdict {
    /// `normal`, `safe` or `stop:<feature id>`.
    init(qaWord word: String) throws {
      switch word {
      case "normal": self = .normal
      case "safe": self = .safeMode
      case let stop where stop.hasPrefix("stop:") && stop.count > "stop:".count:
        self = .stop(String(stop.dropFirst("stop:".count)))
      default:
        throw QAError("launch set= takes normal, safe or stop:<feature id>, not \"\(word)\"")
      }
    }
  }
#endif
