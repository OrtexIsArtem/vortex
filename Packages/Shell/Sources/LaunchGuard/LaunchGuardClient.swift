import ComposableArchitecture
import Foundation
import VortexCore

/// Marks what the shell does with features, on disk and at once, so a crash can be blamed on the right one next launch.
@DependencyClient
struct LaunchGuardClient: Sendable {
  /// Reads how the last launch ended and starts this launch's record. Call once, before any feature's code runs.
  var begin: @Sendable (_ builtIn: Set<FeatureID>) -> LaunchVerdict = { _ in .normal }
  /// Runs `body`, a call into the feature, marked in the record: a crash inside it stops that feature next launch.
  var around: @Sendable (_ id: FeatureID, _ body: () -> Void) -> Void
  /// The launch lived through its first 15 s: a crash outside any call no longer opens safe mode.
  var markStable: @Sendable () -> Void
  /// The feature starts on a trial: for 15 s a crash stops it, or opens safe mode while others are on trial too.
  var beginTrial: @Sendable (_ id: FeatureID) -> Void
}

extension LaunchGuardClient: DependencyKey {
  static let liveValue: LaunchGuardClient = {
    let log = LaunchLog(folder: DataFolder.url)
    return LaunchGuardClient(
      begin: { builtIn in
        var verdict = log.begin(builtIn: builtIn)
        #if DEBUG
          // QA's `launch set=…` decides this launch instead.
          if let forced = LaunchQA.takeNextVerdict() { verdict = forced }
        #endif
        // From here on a crash leaves its mark for the next launch.
        CrashSignals.install(markerPath: log.markerURL.path)
        return verdict
      },
      around: { id, body in log.around(id, body) },
      markStable: { log.markStable() },
      beginTrial: { log.beginTrial($0) }
    )
  }()

  /// Unimplemented, except that a call into a feature still runs.
  static let testValue: LaunchGuardClient = {
    var client = LaunchGuardClient()
    client.around = { _, body in body() }
    return client
  }()
}

extension DependencyValues {
  var launchGuard: LaunchGuardClient {
    get { self[LaunchGuardClient.self] }
    set { self[LaunchGuardClient.self] = newValue }
  }
}

/// The launch record in `launch.json` and the crash mark in `crash.marker`, both in the data folder. Every change is
/// written at once and atomically, so the file is current whenever Vortex crashes.
final class LaunchLog: @unchecked Sendable {
  let folder: URL
  private let trialLength: Duration
  /// Guards `record`, which every change reads and writes.
  private let lock = NSLock()
  private var record: LaunchRecord?

  init(folder: URL, trialLength: Duration = .seconds(15)) {
    self.folder = folder
    self.trialLength = trialLength
  }

  var recordURL: URL { folder.appending(path: "launch.json") }
  /// `CrashSignals` writes a byte here as Vortex crashes.
  var markerURL: URL { folder.appending(path: "crash.marker") }

  func begin(builtIn: Set<FeatureID>) -> LaunchVerdict {
    let previous = (try? Data(contentsOf: recordURL)).flatMap { try? JSONDecoder().decode(LaunchRecord.self, from: $0) }
    let size = (try? FileManager.default.attributesOfItem(atPath: markerURL.path)[.size] as? Int) ?? 0
    try? FileManager.default.removeItem(at: markerURL)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    update(start: LaunchRecord(startedAt: .now, calling: nil, isStable: false, trials: [:]))
    return LaunchVerdict.verdict(after: previous, crashed: size > 0, builtIn: builtIn)
  }

  func around(_ id: FeatureID, _ body: () -> Void) {
    var outer: FeatureID?
    update { outer = $0.calling; $0.calling = id }
    body()
    update { $0.calling = outer }
  }

  func markStable() {
    update { $0.isStable = true }
  }

  func beginTrial(_ id: FeatureID) {
    let startedAt = Date.now
    update { $0.trials[id] = startedAt }
    Task { [trialLength] in
      try? await Task.sleep(for: trialLength)
      // A later trial of the same feature keeps its own 15 s.
      self.update { if $0.trials[id] == startedAt { $0.trials[id] = nil } }
    }
  }

  private func update(start: LaunchRecord? = nil, _ change: (inout LaunchRecord) -> Void = { _ in }) {
    lock.withLock {
      guard var next = start ?? record else { return }
      change(&next)
      guard next != record else { return }
      record = next
      try? JSONEncoder().encode(next).write(to: recordURL, options: .atomic)
    }
  }
}
