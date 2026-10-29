import Foundation
import SwiftUI
import Testing

@testable import VortexCore

struct PermissionsTests {
  @Test
  func onlyScreenRecordingAndThePasteboardWaitForARelaunch() {
    #expect(Permission.allCases.filter(\.needsRelaunch) == [.screenRecording, .pasteboard])
  }

  @Test
  func onlyNotificationsAreGrantedInMacOSsOwnPrompt() {
    #expect(Permission.allCases.filter(\.isGrantedInPlace) == [.notifications])
  }

  /// The names are stored (the onboarding's saved page, QA state), so they never change.
  @Test
  func namesAreStable() {
    #expect(Permission.allCases.map(\.rawValue) == ["notifications", "accessibility", "screenRecording", "pasteboard"])
    #expect(
      [PermissionStatus.notGranted, .granted, .grantedAfterRestart, .notNeeded].map(\.rawValue)
        == ["notGranted", "granted", "grantedAfterRestart", "notNeeded"]
    )
  }

  @Test
  func everyPermissionHasATitleAndAWarningOfItsOwn() {
    #expect(Set(Permission.allCases.map(\.title.key)).count == Permission.allCases.count)
    #expect(Set(Permission.allCases.map(\.offLabel.key)).count == Permission.allCases.count)
  }

  @Test
  func theCheckboxIsOnForAGrantEvenOneThatWaitsForARelaunch() {
    #expect(PermissionStatus.granted.isOn)
    #expect(PermissionStatus.grantedAfterRestart.isOn)
    #expect(!PermissionStatus.notGranted.isOn)
    #expect(!PermissionStatus.notNeeded.isOn)
  }

  @Test
  func statusesEncodeAsAnObjectByPermission() throws {
    let statuses: [Permission: PermissionStatus] = [.accessibility: .granted]
    let json = try JSONEncoder().encode(statuses)
    #expect(String(decoding: json, as: UTF8.self) == #"{"accessibility":"granted"}"#)
    #expect(try JSONDecoder().decode([Permission: PermissionStatus].self, from: json) == statuses)
  }
}

@MainActor
struct FeatureModulePermissionsTests {
  enum Plain: FeatureModule {
    static let id: FeatureID = "plain"
    static let title: LocalizedStringResource = "Plain"
    static let symbol = "circle"
    static func makeTab() -> AnyView { AnyView(EmptyView()) }
  }

  enum Needy: FeatureModule {
    static let id: FeatureID = "needy"
    static let title: LocalizedStringResource = "Needy"
    static let symbol = "circle"
    static let permissionNeeds = [PermissionNeed(.screenRecording, reason: "Turns a screenshot into a new task.")]
    static func makeTab() -> AnyView { AnyView(EmptyView()) }
    static func makeOnboardingStep() -> OnboardingStep? {
      OnboardingStep(id: id, title: "Step", view: EmptyView())
    }
  }

  @Test
  func aFeatureNeedsNoPermissionAndHasNoStepUnlessItSaysSo() {
    #expect(Plain.permissionNeeds.isEmpty)
    #expect(Plain.makeOnboardingStep() == nil)
    #expect(Plain.descriptor.permissionNeeds.isEmpty)
  }

  @Test
  func theDescriptorCarriesTheNeeds() {
    #expect(Needy.descriptor.permissionNeeds == Needy.permissionNeeds)
    #expect(Needy.descriptor.permissionNeeds.map(\.permission) == [.screenRecording])
    #expect(Needy.makeOnboardingStep()?.id == "needy")
  }
}

struct PermissionPageTests {
  @Test
  func theShellGetsEveryRequestWhileItListens() async {
    let channel = PermissionPageChannel()
    var requests = channel.requests().makeAsyncIterator()
    channel.send(.accessibility)
    channel.send(.screenRecording)
    #expect(await requests.next() == .accessibility)
    #expect(await requests.next() == .screenRecording)
  }

  @Test
  func theLatestRequestMadeBeforeTheShellListensWaitsForIt() async {
    let channel = PermissionPageChannel()
    channel.send(.notifications)
    channel.send(.pasteboard)
    var requests = channel.requests().makeAsyncIterator()
    channel.send(.accessibility)
    #expect(await requests.next() == .pasteboard)
    #expect(await requests.next() == .accessibility)
  }

  @Test
  func everyListenerGetsEveryRequest() async {
    let channel = PermissionPageChannel()
    var first = channel.requests().makeAsyncIterator()
    var second = channel.requests().makeAsyncIterator()
    channel.send(.screenRecording)
    #expect(await first.next() == .screenRecording)
    #expect(await second.next() == .screenRecording)
  }

  @Test
  func aListenerThatStoppedNoLongerTakesRequests() async {
    let channel = PermissionPageChannel()
    let stopped = Task {
      var requests = channel.requests().makeAsyncIterator()
      return await requests.next()
    }
    stopped.cancel()
    #expect(await stopped.value == nil)
    // With nobody listening, the request waits for the next listener instead of going to the one that stopped.
    channel.send(.accessibility)
    var requests = channel.requests().makeAsyncIterator()
    #expect(await requests.next() == .accessibility)
  }

  @Test
  func theTestValueIsUnimplemented() async {
    await withKnownIssue {
      await PermissionPage.testValue.open(.accessibility)
    }
  }
}
