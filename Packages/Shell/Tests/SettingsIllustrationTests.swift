import ComposableArchitecture
import Testing
import VortexCore
import VortexPlatform

@testable import VortexShell

/// The drawn System Settings names its panes as this Mac's System Settings does, in the system's language; without a
/// name of macOS's, a breadcrumb is Vortex's own, whole, so it never mixes two languages. `swift test` builds no
/// String Catalog, so Vortex's own words read as their English keys here.
@MainActor
struct SettingsIllustrationTests {
  static let german = SystemSettingsNames(
    privacyAndSecurity: "Datenschutz & Sicherheit",
    accessibility: "Bedienungshilfen",
    screenRecording: "Aufnahme von Bildschirm & Systemaudio",
    pasteFromOtherApps: "Aus anderen Apps einsetzen",
    notifications: "Mitteilungen",
    allowNotifications: "Mitteilungen erlauben"
  )

  @Test
  func theBreadcrumbAndTheRowUseSystemSettingsOwnNames() {
    let names = Self.german
    #expect(IllustrationText.breadcrumb(.accessibility, names) == "Datenschutz & Sicherheit › Bedienungshilfen")
    #expect(IllustrationText.breadcrumb(.screenRecording, names) == "Datenschutz & Sicherheit › Aufnahme von Bildschirm & Systemaudio")
    #expect(IllustrationText.breadcrumb(.pasteboard, names) == "Datenschutz & Sicherheit › Aus anderen Apps einsetzen")
    #expect(IllustrationText.breadcrumb(.notifications, names) == "Mitteilungen › Vortex")
    #expect(IllustrationText.rowTitle(.notifications, names) == "Mitteilungen erlauben")
    #expect(IllustrationText.rowTitle(.accessibility, names) == "Vortex")
  }

  @Test
  func aNameMacOSDoesntGiveFallsBackToVortexsWholeBreadcrumb() {
    var names = Self.german
    names.pasteFromOtherApps = nil
    names.notifications = nil
    #expect(IllustrationText.breadcrumb(.pasteboard, names) == "Privacy & Security › Paste from Other Apps")
    #expect(IllustrationText.breadcrumb(.accessibility, names) == "Datenschutz & Sicherheit › Bedienungshilfen")
    // The switch's label comes with its pane's name, or not at all.
    #expect(IllustrationText.breadcrumb(.notifications, names) == "Notifications › Vortex")
    #expect(IllustrationText.rowTitle(.notifications, names) == "Allow notifications")

    let none = SystemSettingsNames()
    #expect(IllustrationText.breadcrumb(.screenRecording, none) == "Privacy & Security › Screen & System Audio Recording")
    #expect(IllustrationText.breadcrumb(.accessibility, none) == "Privacy & Security › Accessibility")
  }

  @Test
  func theOnboardingKeepsTheNamesTheShellRead() async {
    let store = TestStore(initialState: OnboardingFeature.State()) { OnboardingFeature() }
    await store.send(.systemSettingsNamesLoaded(Self.german)) { $0.settingsNames = Self.german }
  }
}
