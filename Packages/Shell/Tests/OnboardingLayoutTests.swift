import AppKit
import ComposableArchitecture
import SwiftUI
import Testing
import VortexCore
import VortexPlatform

@testable import VortexShell

/// No text is cut short (S31; A-B2, B-B1): with every text at its full length, each page's title and content fit the
/// window above its footer, in their longest states. A page that grew past it would scroll (`FittingPage`), but no
/// page should need to in English; Ukrainian is checked on QA snapshots, as `swift test` doesn't build the catalogs.
@MainActor
struct OnboardingLayoutTests {
  func store(
    _ progress: OnboardingProgress = .finished,
    presentation: OnboardingFeature.Presentation,
    statuses: [Permission: PermissionStatus] = OnboardingNeeds.allOff,
    configure: (inout OnboardingFeature.State) -> Void = { _ in }
  ) -> StoreOf<OnboardingFeature> {
    @Shared(.permissionStatuses) var shared
    $shared.withLock { $0 = statuses }
    var state = OnboardingFeature.State(progress: progress)
    state.catalog = PermissionCatalog(features: OnboardingNeeds.all, required: [.screenRecording])
    state.presentation = presentation
    configure(&state)
    return Store(initialState: state) { OnboardingFeature() }
  }

  /// The column's height with every text in full, at the window's width.
  func fullHeight(_ column: some View) -> CGFloat {
    let host = NSHostingView(rootView: column.frame(width: FittingPage<EmptyView>.columnSpace.width))
    return host.fittingSize.height
  }

  func expectFits(_ column: some View, _ page: String) {
    let height = fullHeight(column)
    let space = FittingPage<EmptyView>.columnSpace.height
    // A real measurement: every column holds at least a title, rows and their text.
    #expect(height > 200, "\(page): measured \(height) pt")
    #expect(height <= space, "\(page): \(height) pt of text and content, \(space) pt of room")
    print("layout \(page): \(Int(height)) of \(Int(space)) pt")
  }

  /// The pasteboard's single page, still off after "Restart to check": S59's hint and the relaunch note.
  @Test
  func thePasteboardsSinglePageWithItsHintFits() {
    let store = store(presentation: .single(.init(permission: .pasteboard, kind: .afterRelaunch), .window)) {
      $0.checkedAtLaunch = [.pasteboard]
    }
    #expect(store.state.showsRecheckHint(.pasteboard))
    expectFits(SinglePermissionPage(store: store, single: store.single!).column, "pasteboard after relaunch")
  }

  /// The pasteboard's single page waiting for its check: "Checked after restart", the note and "Restart to check".
  @Test
  func thePasteboardsSinglePageWaitingForItsCheckFits() {
    var progress = OnboardingProgress.finished
    progress.pendingChecks = [.pasteboard]
    let store = store(progress, presentation: .single(.init(permission: .pasteboard, kind: .request), .window))
    #expect(store.state.showsRestartToCheck(.pasteboard))
    expectFits(SinglePermissionPage(store: store, single: store.single!).column, "pasteboard waiting")
  }

  /// Screen Recording's single page with every line it can have: the hint and both notes.
  @Test
  func screenRecordingsSinglePageWithEveryLineFits() {
    let store = store(presentation: .single(.init(permission: .screenRecording, kind: .request), .window)) {
      $0.settingsOpened = [.screenRecording]
    }
    #expect(store.state.showsRecheckHint(.screenRecording))
    expectFits(SinglePermissionPage(store: store, single: store.single!).column, "screen recording")
  }

  @Test
  func thePageTheRefusedLockOpenedFits() {
    let store = store(
      presentation: .single(.init(permission: .accessibility, kind: .lockRefused), .window),
      statuses: [.accessibility: .granted]
    )
    expectFits(SinglePermissionPage(store: store, single: store.single!).column, "lock refused")
  }

  /// The onboarding's Screen Recording page, required and off, with the hint and both notes.
  @Test
  func theOnboardingsScreenRecordingPageFits() {
    let store = store(.at(.permission(.screenRecording)), presentation: .flow(.window)) {
      $0.settingsOpened = [.screenRecording]
    }
    let page = PageScaffold(store: store, title: Text(Permission.screenRecording.title)) {
      HardPermissionContent(store: store, permission: .screenRecording, isSingle: false)
    }
    expectFits(page.column, "onboarding screen recording")
  }

  /// The onboarding's pasteboard page after its pane: ↻, the note and "Restart to check".
  @Test
  func theOnboardingsPasteboardPageWaitingForItsCheckFits() {
    var progress = OnboardingProgress.at(.permission(.pasteboard))
    progress.pendingChecks = [.pasteboard]
    let store = store(progress, presentation: .flow(.window))
    let page = PageScaffold(store: store, title: Text(Permission.pasteboard.title)) {
      HardPermissionContent(store: store, permission: .pasteboard, isSingle: false)
    }
    expectFits(page.column, "onboarding pasteboard")
  }

  /// Basics with the notification hint and the Login Items caption.
  @Test
  func basicsWithEveryLineFits() {
    let store = store(.at(.basics), presentation: .flow(.window)) {
      $0.isNotificationHintVisible = true
      $0.loginItem = .requiresApproval
    }
    let page = PageScaffold(store: store, title: Text("Basics", bundle: .module)) {
      BasicsContent(store: store)
    }
    expectFits(page.column, "basics")
  }

  /// Done with a row per permission, Required on one, and the longest hint.
  @Test
  func doneWithEveryRowFits() {
    let store = store(.at(.done), presentation: .flow(.window)) {
      $0.doneHint = .init(notch: .click, menuBarIcon: false)
      $0.openShortcut = "⌃⌥⌘V"
    }
    expectFits(DonePage(store: store).column, "done")
  }
}
