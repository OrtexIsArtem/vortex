import Foundation
import VortexCore

/// What the shell knows about the current launch, kept in `DataFolder/launch.json` so the next launch can tell what the
/// shell was doing if Vortex crashed.
struct LaunchRecord: Codable, Equatable, Sendable {
  var startedAt: Date
  /// The feature the shell is calling right now: starting or stopping it, or making one of its views; nil between calls.
  var calling: FeatureID?
  /// The launch lived through its first 15 s.
  var isStable: Bool
  /// Features started on a trial (Add, Start, Try Again, Start All), each kept here for 15 s from its start.
  var trials: [FeatureID: Date]
}

/// What the next launch does after the last one ended.
enum LaunchVerdict: Equatable, Sendable {
  case normal
  /// The feature Vortex crashed in stays off until the user tries it again.
  case stop(FeatureID)
  /// Vortex crashed early and nobody can be blamed: no feature starts this launch until the user starts them.
  case safeMode

  /// Only a crash mark counts: a kill (Xcode's Stop, Force Quit, a second copy taking over) leaves none and changes
  /// nothing. A crash in a call to a feature stops that feature, unless it is built in; a crash during one trial stops
  /// the tried feature; a crash during several trials, inside a built-in feature or in the first 15 s outside any call
  /// opens safe mode. A later crash nobody can be blamed for changes nothing. Calls run on the main thread, so a crash on
  /// another thread (`offMainThread`) is never blamed on the call in progress.
  static func verdict(
    after previous: LaunchRecord?,
    crashed: Bool,
    offMainThread: Bool = false,
    builtIn: Set<FeatureID>
  ) -> LaunchVerdict {
    guard crashed, let previous else { return .normal }
    if !offMainThread, let calling = previous.calling {
      return builtIn.contains(calling) ? .safeMode : .stop(calling)
    }
    if previous.trials.count == 1, let tried = previous.trials.keys.first {
      return .stop(tried)
    }
    if previous.trials.count > 1 || !previous.isStable {
      return .safeMode
    }
    return .normal
  }
}
