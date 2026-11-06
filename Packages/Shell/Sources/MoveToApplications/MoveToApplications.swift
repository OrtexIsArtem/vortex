import ComposableArchitecture
import Foundation
import VortexPlatform

/// A release build kept outside /Applications and ~/Applications offers, before anything else of it starts, to move
/// itself to /Applications (behavior.md, "Moving to Applications"). ShellController calls it; debug builds never do.
@MainActor
struct MoveToApplications {
  /// Where Vortex moves.
  nonisolated static let destination = URL(fileURLWithPath: "/Applications/Vortex.app")

  enum Decision: Equatable, Sendable {
    /// Starts as usual, without asking.
    case run
    /// Asks; `replacesOlder`: a Vortex of the same or an older version is there, and goes to the Trash.
    case ask(replacesOlder: Bool)
  }

  enum Answer: Equatable, Sendable {
    case move
    case notNow(dontAskAgain: Bool)
  }

  @Dependency(\.appInstallClient) var install
  @Dependency(\.moveAlert) var alert
  @Dependency(\.systemClient) var system

  /// Asks only for a copy kept outside /Applications and ~/Applications, at any depth (under App Translocation, where
  /// its original is), never after "Don't ask again", and not when the app at /Applications/Vortex.app is a newer
  /// Vortex, compared as numbers, or another app, which never goes to the Trash for it.
  nonisolated static func decide(_ copy: AppCopy, installed: InstalledApp?, home: URL, isDeclined: Bool) -> Decision {
    if isKeptInApplications(copy.location, home: home) || isDeclined { return .run }
    guard let installed else { return .ask(replacesOlder: false) }
    guard installed.bundleID == copy.bundleID else { return .run }
    if AppVersion.isNewer(installed.version ?? "", than: copy.version) { return .run }
    return .ask(replacesOlder: true)
  }

  /// Inside /Applications or ~/Applications, at any depth. macOS may spell /Applications through the data volume.
  nonisolated static func isKeptInApplications(_ location: URL, home: URL) -> Bool {
    var path = location.standardizedFileURL.path
    let dataVolume = "/System/Volumes/Data"
    if path.hasPrefix(dataVolume + "/") { path.removeFirst(dataVolume.count) }
    let folders = ["/Applications", home.standardizedFileURL.appending(path: "Applications").path]
    return folders.contains { path.hasPrefix($0 + "/") }
  }

  /// Asks when the decision says so, and moves when the user agrees. True when Vortex moved: it quits and opens again
  /// from /Applications, so nothing else of this launch should start. A failure says so and Vortex runs on from where
  /// it is.
  func offer(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
    guard let copy = install.current() else { return false }
    let decision = Self.decide(
      copy,
      installed: install.app(Self.destination),
      home: home,
      isDeclined: install.isMoveDeclined()
    )
    guard case let .ask(replacesOlder) = decision else { return false }
    switch alert.ask(replacesOlder) {
    case let .notNow(dontAskAgain):
      if dontAskAgain { install.declineMove() }
      return false
    case .move:
      do {
        try install.move(copy, Self.destination)
      } catch {
        alert.showFailure()
        return false
      }
      // Once the launch has gone on to its end: the helper opens /Applications/Vortex.app after this process is gone,
      // so the one-instance rule never meets two of them.
      let system = system
      Task { await system.relaunchFrom(Self.destination) }
      return true
    }
  }
}
