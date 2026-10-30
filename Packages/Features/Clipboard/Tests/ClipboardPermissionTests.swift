import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureClipboard

/// Paste from Other Apps: the settings row and nothing read or recorded while it is off.
@MainActor
struct ClipboardPermissionTests {
  let pages = LockIsolated<[Permission]>([])
  let refreshes = LockIsolated(0)
  let relaunches = LockIsolated(0)
  /// How often the pasteboard was watched, and the copies made in other apps while it was.
  let watches = LockIsolated(0)
  let copies = LockIsolated<AsyncStream<PasteboardCopy>.Continuation?>(nil)

  func makeStore() -> TestStoreOf<ClipboardFeature> {
    let store = TestStore(initialState: ClipboardFeature.State()) {
      ClipboardFeature()
    } withDependencies: {
      $0.database = VortexDatabase.inMemory()
      $0.date = .constant(Date(timeIntervalSinceReferenceDate: 800_000_000))
      $0.uuid = .incrementing
      $0.pasteboardClient.copies = { [watches, copies] in
        watches.withValue { $0 += 1 }
        let (stream, continuation) = AsyncStream.makeStream(of: PasteboardCopy.self)
        copies.setValue(continuation)
        return stream
      }
      $0.fileClient.contents = { _ in [] }
      $0.appsClient.running = { [] }
      $0.permissionPage.open = { [pages] permission in pages.withValue { $0.append(permission) } }
      $0.permissionsClient.refresh = { [refreshes] in refreshes.withValue { $0 += 1 } }
      $0.systemClient.relaunch = { [relaunches] in relaunches.withValue { $0 += 1 } }
    }
    store.exhaustivity = .off
    return store
  }

  func eventually(_ condition: @escaping @Sendable () -> Bool) async throws {
    for _ in 0..<200 where !condition() {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(condition())
  }

  @Test
  func whilePasteFromOtherAppsIsOffThePasteboardIsNotReadAndNothingIsRecorded() async throws {
    let simulated = SimulatedPermissions()
    simulated.setPasteboardAsks(true)
    simulated.set(.pasteboard, to: .denied)
    #expect(simulated.statuses[.pasteboard] == .notGranted)
    @Shared(.permissionStatuses) var statuses
    $statuses.withLock { $0 = simulated.statuses }

    let store = makeStore()
    await store.send(.start)
    await store.receive(\.loaded)
    try await Task.sleep(for: .milliseconds(50))
    #expect(watches.value == 0)

    // Allowed in System Settings, seen after the relaunch: watching starts and copies are kept.
    simulated.toggle(.pasteboard, on: true)
    simulated.relaunch()
    $statuses.withLock { $0 = simulated.statuses }
    #expect(statuses[.pasteboard] == .notNeeded)
    try await eventually { [watches] in watches.value == 1 }
    copies.value?.yield(PasteboardCopy(content: .text("kept"), isConcealed: false, source: nil, frontApps: []))
    await store.receive(\.copied)
    #expect(store.state.items.map(\.content) == [.text("kept")])

    // Off again: the watch stops, and a copy made then is never read.
    $statuses.withLock { $0[.pasteboard] = .notGranted }
    try await Task.sleep(for: .milliseconds(50))
    copies.value?.yield(PasteboardCopy(content: .text("not kept"), isConcealed: false, source: nil, frontApps: []))
    try await Task.sleep(for: .milliseconds(50))
    #expect(store.state.items.map(\.content) == [.text("kept")])
    #expect(watches.value == 1)
    await store.send(.stop)
  }

  /// Before the first read, and with the pasteboard not needed (macOS 26.4), copies are kept as always.
  @Test
  func unknownOrNotNeededReadsThePasteboard() {
    #expect(ClipboardFeature.mayReadPasteboard([:]))
    #expect(ClipboardFeature.mayReadPasteboard([.pasteboard: .notNeeded]))
    #expect(ClipboardFeature.mayReadPasteboard([.pasteboard: .granted]))
    #expect(ClipboardFeature.mayReadPasteboard([.pasteboard: .grantedAfterRestart]))
    #expect(!ClipboardFeature.mayReadPasteboard([.pasteboard: .notGranted]))
  }

  @Test
  func theSettingsRowOpensThePageRestartsAndReadsAgain() async {
    let store = makeStore()
    await store.send(.settingsShown).finish()
    #expect(refreshes.value == 1)
    await store.send(.turnOnTapped(.pasteboard)).finish()
    #expect(pages.value == [.pasteboard])
    await store.send(.restartTapped).finish()
    #expect(relaunches.value == 1)
  }
}
