#if DEBUG
  import Foundation

  /// The `--qa <name>` launch argument of a debug build, with its options. It starts QA mode: a copy of Vortex isolated
  /// from the user's own, driven by commands, see VortexPlatform's `QA`. Read here because `DataFolder` depends on it.
  public enum QALaunch: Equatable, Sendable {
    /// Started without `--qa`: nothing changes.
    case none
    /// Started with `--qa <name>`, the name 1–16 letters, digits or dashes.
    case named(String, Options)
    /// A bad name, no name, `--qa` twice, an unknown `--qa-…` option, or options without `--qa`. Such a process must not
    /// start at all: running as plain Vortex would touch the user's data and services.
    case invalid(String)

    /// What a QA run pretends about the Mac.
    public struct Options: Equatable, Sendable {
      /// `--qa-reduce-motion`: Reduce Motion on, whatever macOS says.
      public var reduceMotion = false
      /// `--qa-release`: the behaviors only release builds have, such as applying the login item.
      public var releaseBehavior = false
      /// `--qa-screens notch|plain|notch+plain`: the displays, the main one first; nil: those of this Mac.
      public var screens: [Screen]?

      public init(reduceMotion: Bool = false, releaseBehavior: Bool = false, screens: [Screen]? = nil) {
        self.reduceMotion = reduceMotion
        self.releaseBehavior = releaseBehavior
        self.screens = screens
      }
    }

    /// A display: with a notch, like a MacBook's, or without one.
    public enum Screen: String, Equatable, Sendable {
      case notch
      case plain
    }

    /// This process's.
    public static let current = QALaunch(arguments: ProcessInfo.processInfo.arguments)

    /// From the arguments as `ProcessInfo.arguments` gives them, the executable first. Every argument spelled like
    /// `--qa…` must be one of QA's, so a typo stops the app rather than starting plain Vortex.
    public init(arguments: [String]) {
      let words = Array(arguments.dropFirst())
      var name: String?
      var options = Options()
      var given: Set<String> = []
      var index = 0
      while index < words.count {
        let word = words[index]
        guard word.lowercased().hasPrefix("--qa") else {
          index += 1
          continue
        }
        guard given.insert(word).inserted else {
          self = .invalid("\(word) is given more than once")
          return
        }
        let value = words.indices.contains(index + 1) ? words[index + 1] : nil
        switch word {
        case "--qa":
          // Another `--qa…` right after it is an option, so the name is missing.
          guard let value, Self.isValidName(value), !value.lowercased().hasPrefix("--qa") else {
            self = .invalid("--qa needs a name of 1–16 letters, digits or dashes, not \"\(value ?? "")\"")
            return
          }
          name = value
          index += 2
        case "--qa-reduce-motion":
          options.reduceMotion = true
          index += 1
        case "--qa-release":
          options.releaseBehavior = true
          index += 1
        case "--qa-screens":
          guard let value, let screens = Self.screens(value) else {
            self = .invalid("--qa-screens takes notch, plain or notch+plain, not \"\(value ?? "")\"")
            return
          }
          options.screens = screens
          index += 2
        default:
          self = .invalid("unknown QA option \(word): there are --qa <name>, --qa-reduce-motion, --qa-release and --qa-screens")
          return
        }
      }
      guard let name else {
        self = given.isEmpty ? .none : .invalid("QA options need --qa <name>")
        return
      }
      self = .named(name, options)
    }

    /// The run's name; nil without `--qa` or with a bad one.
    public var name: String? {
      if case let .named(name, _) = self { name } else { nil }
    }

    /// The run's options; nil outside QA mode.
    public var options: Options? {
      if case let .named(_, options) = self { options } else { nil }
    }

    /// 1–16 letters, digits or dashes: `[A-Za-z0-9-]{1,16}`.
    public static func isValidName(_ name: String) -> Bool {
      (1...16).contains(name.unicodeScalars.count) && name.unicodeScalars.allSatisfy { scalar in
        scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-")
      }
    }

    /// `notch`, `plain` or up to three of them joined by `+`, such as `notch+plain`; nil for anything else.
    public static func screens(_ text: String) -> [Screen]? {
      let screens = text.split(separator: "+", omittingEmptySubsequences: false).map { Screen(rawValue: String($0)) }
      guard (1...3).contains(screens.count), !screens.contains(nil) else { return nil }
      return screens.compactMap(\.self)
    }

    /// Stops a process started with a bad `--qa` before it touches anything, with the reason on standard error.
    public func stopIfInvalid() {
      guard case let .invalid(reason) = self else { return }
      FileHandle.standardError.write(Data("Vortex: not started: \(reason)\n".utf8))
      exit(64)
    }
  }
#endif
