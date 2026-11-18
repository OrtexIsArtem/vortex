import Foundation
import Testing
import VortexCore

@testable import VortexShell

extension LaunchRecord {
  /// A launch that ended within its first 15 s.
  static func early(calling: FeatureID? = nil, trials: [FeatureID] = []) -> Self {
    LaunchRecord(startedAt: .distantPast, calling: calling, isStable: false, trials: trials.trialDates)
  }

  /// A launch that ended after its first 15 s.
  static func stable(calling: FeatureID? = nil, trials: [FeatureID] = []) -> Self {
    LaunchRecord(startedAt: .distantPast, calling: calling, isStable: true, trials: trials.trialDates)
  }
}

extension [FeatureID] {
  fileprivate var trialDates: [FeatureID: Date] {
    Dictionary(uniqueKeysWithValues: map { ($0, Date.distantPast) })
  }
}

struct LaunchVerdictTests {
  /// Stopping Vortex from Xcode, Force Quit or a second copy taking over leaves no crash mark: nothing changes.
  @Test
  func aKillIsNotACrash() {
    #expect(LaunchVerdict.verdict(after: .early(calling: "tasks"), crashed: false, builtIn: []) == .normal)
    #expect(LaunchVerdict.verdict(after: nil, crashed: true, builtIn: []) == .normal)
  }

  @Test
  func aCrashWhileCallingAFeatureStopsOnlyIt() {
    #expect(LaunchVerdict.verdict(after: .early(calling: "tasks"), crashed: true, builtIn: ["home"]) == .stop("tasks"))
    #expect(
      LaunchVerdict.verdict(after: .stable(calling: "tasks", trials: ["clipboard"]), crashed: true, builtIn: [])
        == .stop("tasks")
    )
  }

  @Test
  func aCrashDuringOneTrialStopsTheTriedFeature() {
    #expect(LaunchVerdict.verdict(after: .stable(trials: ["clipboard"]), crashed: true, builtIn: []) == .stop("clipboard"))
    #expect(LaunchVerdict.verdict(after: .early(trials: ["clipboard"]), crashed: true, builtIn: []) == .stop("clipboard"))
  }

  @Test
  func aCrashDuringSeveralTrialsOrEarlyWithoutAMarkGoesToSafeMode() {
    #expect(
      LaunchVerdict.verdict(after: .stable(trials: ["clipboard", "tasks"]), crashed: true, builtIn: []) == .safeMode
    )
    #expect(LaunchVerdict.verdict(after: .early(), crashed: true, builtIn: []) == .safeMode)
  }

  /// Home always runs: a crash inside it can't stop it, so the next launch is safe instead.
  @Test
  func homeIsNeverStopped() {
    #expect(LaunchVerdict.verdict(after: .early(calling: "home"), crashed: true, builtIn: ["home"]) == .safeMode)
  }

  /// A crash after the first 15 s, outside any call and trial, has nobody to blame: the next launch is as usual.
  @Test
  func aLateCrashNobodyCanBeBlamedForChangesNothing() {
    #expect(LaunchVerdict.verdict(after: .stable(), crashed: true, builtIn: []) == .normal)
  }
}

/// The record on disk, in a folder of the test's own.
struct LaunchLogTests {
  let folder = URL.temporaryDirectory.appending(path: "LaunchLogTests-\(UUID().uuidString)", directoryHint: .isDirectory)

  func write(_ record: LaunchRecord) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try JSONEncoder().encode(record).write(to: folder.appending(path: "launch.json"))
  }

  func markCrash() throws {
    try Data([1]).write(to: folder.appending(path: "crash.marker"))
  }

  func recordOnDisk() throws -> LaunchRecord {
    try JSONDecoder().decode(LaunchRecord.self, from: Data(contentsOf: folder.appending(path: "launch.json")))
  }

  @Test
  func aCrashMarkDecidesTheNextLaunchOnce() throws {
    try write(.early(calling: "tasks"))
    try markCrash()
    let log = LaunchLog(folder: folder)
    #expect(log.begin(builtIn: ["home"]) == .stop("tasks"))
    #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "crash.marker").path))
    let record = try recordOnDisk()
    #expect(record.calling == nil && !record.isStable && record.trials.isEmpty)
    // The next launch finds no mark: this one ended without a crash.
    #expect(LaunchLog(folder: folder).begin(builtIn: ["home"]) == .normal)
  }

  /// A fresh install has no folder yet: the record makes it.
  @Test
  func theFirstLaunchStartsTheRecord() throws {
    #expect(LaunchLog(folder: folder).begin(builtIn: []) == .normal)
    #expect(try recordOnDisk().calling == nil)
  }

  @Test
  func aCallIsOnDiskWhileItRuns() throws {
    let log = LaunchLog(folder: folder)
    _ = log.begin(builtIn: [])
    var callingInside: FeatureID?
    log.around("timer") { callingInside = try? recordOnDisk().calling }
    #expect(callingInside == "timer")
    #expect(try recordOnDisk().calling == nil)
  }

  @Test
  func stableAndTrialsAreOnDiskAndATrialEnds() async throws {
    let log = LaunchLog(folder: folder, trialLength: .milliseconds(50))
    _ = log.begin(builtIn: [])
    log.markStable()
    log.beginTrial("clipboard")
    #expect(try recordOnDisk().isStable)
    #expect(try recordOnDisk().trials.keys.sorted() == ["clipboard"])
    for _ in 0..<100 where try !recordOnDisk().trials.isEmpty {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(try recordOnDisk().trials.isEmpty)
  }
}
