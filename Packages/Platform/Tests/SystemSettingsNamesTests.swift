import Foundation
import Testing

@testable import VortexPlatform

/// System Settings' names, read from its own files: in the system's language and as this macOS version names its panes.
struct SystemSettingsNamesTests {
  typealias Tables = [String: [String: [String: String]]]

  let root = FileManager.default.temporaryDirectory.appending(path: "vortex-settings-\(UUID().uuidString)", directoryHint: .isDirectory)

  /// A stand-in for an extension of System Settings: tables by name, then language, then key; as one loctable each,
  /// as macOS 14 and later keep them, or as `<language>.lproj/<table>.strings`.
  func appex(_ name: String, _ tables: Tables, asLproj: Bool = false) throws {
    let resources = root.appending(path: "\(name).appex/Contents/Resources", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    for (table, languages) in tables {
      if asLproj {
        for (language, strings) in languages {
          let folder = resources.appending(path: "\(language).lproj", directoryHint: .isDirectory)
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          try PropertyListSerialization.data(fromPropertyList: strings, format: .binary, options: 0)
            .write(to: folder.appending(path: "\(table).strings"))
        }
      } else {
        var all: [String: Any] = languages
        all["LocProvenance"] = ["en": "1"]
        try PropertyListSerialization.data(fromPropertyList: all, format: .binary, options: 0)
          .write(to: resources.appending(path: "\(table).loctable"))
      }
    }
  }

  static let privacy: Tables = [
    "InfoPlist": [
      "en": ["CFBundleDisplayName": "Privacy & Security"],
      "de": ["CFBundleDisplayName": "Datenschutz & Sicherheit"],
    ],
    "Localizable": [
      "en": [
        "ACCESSIBILITY": "Accessibility",
        "SCREEN_CAPTURE": "Screen Recording",
        "SCREENANDAUDIOCAPTURE": "Screen & System Audio Recording",
        "PASTEBOARD_ACCESS": "Paste from Other Apps",
      ],
      "de": [
        "ACCESSIBILITY": "Bedienungshilfen",
        "SCREEN_CAPTURE": "Bildschirmaufnahme",
        "SCREENANDAUDIOCAPTURE": "Aufnahme von Bildschirm & Systemaudio",
        "PASTEBOARD_ACCESS": "Aus anderen Apps einsetzen",
      ],
    ],
  ]

  static let notifications: Tables = [
    "InfoPlist": ["en": ["CFBundleDisplayName": "Notifications"], "de": ["CFBundleDisplayName": "Mitteilungen"]],
    "Localizable": ["en": ["Allow notifications": "Allow notifications"], "de": ["Allow notifications": "Mitteilungen erlauben"]],
  ]

  /// The first of the user's languages that System Settings has, as macOS picks it: German, not Vortex's English.
  @Test
  func namesComeInTheFirstOfTheSystemsLanguagesThatSystemSettingsHas() throws {
    defer { try? FileManager.default.removeItem(at: root) }
    try appex("SecurityPrivacyExtension", Self.privacy)
    try appex("NotificationsSettings", Self.notifications)
    let names = SystemSettingsStrings.names(languages: ["be-BY", "de-DE", "en-US"], in: root)
    #expect(names == SystemSettingsNames(
      privacyAndSecurity: "Datenschutz & Sicherheit",
      accessibility: "Bedienungshilfen",
      screenRecording: "Aufnahme von Bildschirm & Systemaudio",
      pasteFromOtherApps: "Aus anderen Apps einsetzen",
      notifications: "Mitteilungen",
      allowNotifications: "Mitteilungen erlauben"
    ))
    #expect(SystemSettingsStrings.names(languages: ["en-GB"], in: root).accessibility == "Accessibility")
  }

  /// macOS 14 names the pane Screen Recording: without the newer key, the older one.
  @Test
  func beforeMacOS15ScreenRecordingKeepsItsOldName() throws {
    defer { try? FileManager.default.removeItem(at: root) }
    var privacy = Self.privacy
    privacy["Localizable"]?["en"]?["SCREENANDAUDIOCAPTURE"] = nil
    privacy["Localizable"]?["en"]?["PASTEBOARD_ACCESS"] = nil
    try appex("SecurityPrivacyExtension", privacy)
    let names = SystemSettingsStrings.names(languages: ["en"], in: root)
    #expect(names.screenRecording == "Screen Recording")
    #expect(names.pasteFromOtherApps == nil)
  }

  /// Tables kept per language in lproj folders read the same.
  @Test
  func tablesInLprojFoldersReadTheSame() throws {
    defer { try? FileManager.default.removeItem(at: root) }
    try appex("SecurityPrivacyExtension", Self.privacy, asLproj: true)
    try appex("NotificationsSettings", Self.notifications, asLproj: true)
    let names = SystemSettingsStrings.names(languages: ["de"], in: root)
    #expect(names.privacyAndSecurity == "Datenschutz & Sicherheit")
    #expect(names.screenRecording == "Aufnahme von Bildschirm & Systemaudio")
    #expect(names.allowNotifications == "Mitteilungen erlauben")
  }

  /// Nothing to read, nothing made up: every name is nil, and the caller uses its own words.
  @Test
  func withoutSystemSettingsFilesEveryNameIsMissing() {
    #expect(SystemSettingsStrings.names(languages: ["en"], in: root) == SystemSettingsNames())
  }

  /// The system's languages, never Vortex's own choice, which lives in its own domain.
  @Test
  func theSystemsLanguagesComeFromTheGlobalList() {
    #expect(SystemSettingsStrings.systemLanguages(globalDomain: ["AppleLanguages": ["de-DE", "en-US"]]) == ["de-DE", "en-US"])
    #expect(SystemSettingsStrings.systemLanguages(globalDomain: [:]) == Locale.preferredLanguages)
    #expect(SystemSettingsStrings.systemLanguages(globalDomain: ["AppleLanguages": [String]()]) == Locale.preferredLanguages)
  }

  /// This Mac's own System Settings, in English: the names that every supported macOS has.
  @Test
  func thisMacsSystemSettingsHasItsNames() {
    let names = SystemSettingsStrings.names(languages: ["en"])
    #expect(names.privacyAndSecurity == "Privacy & Security")
    #expect(names.accessibility == "Accessibility")
    #expect(names.notifications == "Notifications")
    #expect(names.screenRecording != nil)
  }
}
