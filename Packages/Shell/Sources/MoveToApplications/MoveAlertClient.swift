import AppKit
import ComposableArchitecture

/// The two alerts of the move to /Applications, as MoveToApplications sees them. Only the shell uses them; each waits
/// for the user.
@DependencyClient
struct MoveAlertClient: Sendable {
  /// "Move Vortex to Applications?", with "Don't ask again"; `replacesOlder` adds that the older Vortex there goes to
  /// the Trash.
  var ask: @Sendable (_ replacesOlder: Bool) -> MoveToApplications.Answer = { _ in .notNow(dontAskAgain: false) }
  /// "Vortex couldn't move to Applications.", and how to do it in Finder.
  var showFailure: @Sendable () -> Void
}

extension MoveAlertClient: DependencyKey {
  /// Standard alerts, run modally on the main thread, where MoveToApplications runs.
  static let liveValue = MoveAlertClient(
    ask: { replacesOlder in
      MainActor.assumeIsolated { MoveAlerts.ask(replacesOlder: replacesOlder) }
    },
    showFailure: {
      MainActor.assumeIsolated { MoveAlerts.showFailure() }
    }
  )

  static let testValue = MoveAlertClient()
}

extension DependencyValues {
  var moveAlert: MoveAlertClient {
    get { self[MoveAlertClient.self] }
    set { self[MoveAlertClient.self] = newValue }
  }
}

@MainActor
enum MoveAlerts {
  /// "Move to Applications" is the default button (Return); "Not Now" takes Esc. The checkbox starts off.
  static func ask(replacesOlder: Bool) -> MoveToApplications.Answer {
    let alert = makeQuestion(replacesOlder: replacesOlder)
    // Vortex has no Dock icon: without this the alert could open behind the app in front.
    NSApp.activate()
    guard alert.runModal() != .alertFirstButtonReturn else { return .move }
    return .notNow(dontAskAgain: alert.suppressionButton?.state == .on)
  }

  static func makeQuestion(replacesOlder: Bool) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = String(localized: "Move Vortex to Applications?", bundle: .module)
    var text = String(localized: "It then opens again from the Applications folder.", bundle: .module)
    if replacesOlder {
      text += " " + String(localized: "The older Vortex there goes to the Trash.", bundle: .module)
    }
    alert.informativeText = text
    alert.addButton(withTitle: String(localized: "Move to Applications", bundle: .module))
    let notNow = alert.addButton(withTitle: String(localized: "Not Now", bundle: .module))
    notNow.keyEquivalent = "\u{1b}"
    alert.showsSuppressionButton = true
    alert.suppressionButton?.title = String(localized: "Don't ask again", bundle: .module)
    alert.suppressionButton?.state = .off
    return alert
  }

  static func showFailure() {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = String(localized: "Vortex couldn't move to Applications.", bundle: .module)
    alert.informativeText = String(localized: "Drag Vortex to the Applications folder in Finder.", bundle: .module)
    NSApp.activate()
    alert.runModal()
  }
}
