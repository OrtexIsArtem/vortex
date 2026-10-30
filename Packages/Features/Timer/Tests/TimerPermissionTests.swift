import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureTimer

/// The Notifications row in the timer's settings; a run never asks macOS.
@MainActor
struct TimerPermissionTests {
  let pages = LockIsolated<[Permission]>([])
  let refreshes = LockIsolated(0)
  let relaunches = LockIsolated(0)

  @Test
  func theSettingsRowOpensThePageRestartsAndReadsAgain() async {
    let simulated = SimulatedPermissions()
    let store = TestStore(initialState: TimerFeature.State()) {
      TimerFeature()
    } withDependencies: {
      $0.soundClient.names = { [] }
      $0.permissionPage.open = { [pages] permission in pages.withValue { $0.append(permission) } }
      $0.permissionsClient = .simulated(simulated)
      $0.permissionsClient.refresh = { [refreshes] in refreshes.withValue { $0 += 1 } }
      $0.systemClient.relaunch = { [relaunches] in relaunches.withValue { $0 += 1 } }
    }
    store.exhaustivity = .off
    await store.send(.settingsShown).finish()
    #expect(refreshes.value == 1)
    await store.send(.turnOnTapped(.notifications)).finish()
    #expect(pages.value == [.notifications])
    await store.send(.restartTapped).finish()
    #expect(relaunches.value == 1)
    // Nothing reached macOS: no prompt, no pane.
    #expect(simulated.state.events.isEmpty)
  }
}
