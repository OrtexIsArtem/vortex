import ComposableArchitecture
import Foundation

/// Names System Settings shows on this Mac, for a drawing of its panes: in the system's language, which may not be
/// Vortex's own, and as this macOS version names them. Nil for a name System Settings' files don't have here.
public struct SystemSettingsNames: Equatable, Sendable {
  /// "Privacy & Security".
  public var privacyAndSecurity: String?
  /// "Accessibility", in Privacy & Security.
  public var accessibility: String?
  /// "Screen & System Audio Recording" from macOS 15 on, "Screen Recording" before.
  public var screenRecording: String?
  /// "Paste from Other Apps".
  public var pasteFromOtherApps: String?
  /// "Notifications".
  public var notifications: String?
  /// The switch on an app's page in Notifications: "Allow notifications".
  public var allowNotifications: String?

  public init(
    privacyAndSecurity: String? = nil,
    accessibility: String? = nil,
    screenRecording: String? = nil,
    pasteFromOtherApps: String? = nil,
    notifications: String? = nil,
    allowNotifications: String? = nil
  ) {
    self.privacyAndSecurity = privacyAndSecurity
    self.accessibility = accessibility
    self.screenRecording = screenRecording
    self.pasteFromOtherApps = pasteFromOtherApps
    self.notifications = notifications
    self.allowNotifications = allowNotifications
  }
}

/// System Settings' own names, read from its files.
@DependencyClient
public struct SystemSettingsNamesClient: Sendable {
  /// Reads them, in about 30 ms: call it off the main thread.
  public var names: @Sendable () async -> SystemSettingsNames = { SystemSettingsNames() }
}

extension SystemSettingsNamesClient: DependencyKey {
  public static let liveValue = SystemSettingsNamesClient(
    names: { SystemSettingsStrings.names(languages: SystemSettingsStrings.systemLanguages()) }
  )

  public static let testValue = SystemSettingsNamesClient()
}

extension DependencyValues {
  public var systemSettingsNamesClient: SystemSettingsNamesClient {
    get { self[SystemSettingsNamesClient.self] }
    set { self[SystemSettingsNamesClient.self] = newValue }
  }
}

/// Reads System Settings' strings from the tables of its extensions: `<table>.loctable`, which holds every language,
/// or `<language>.lproj/<table>.strings`.
enum SystemSettingsStrings {
  static let extensions = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions", isDirectory: true)

  /// The languages the user chose for macOS, in order: the global list, which Vortex's own choice (its domain's
  /// AppleLanguages, or `-AppleLanguages` in a QA run) leaves alone.
  static func systemLanguages(
    globalDomain: [String: Any]? = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
  ) -> [String] {
    (globalDomain?["AppleLanguages"] as? [String]).flatMap { $0.isEmpty ? nil : $0 } ?? Locale.preferredLanguages
  }

  static func names(languages: [String], in extensions: URL = extensions) -> SystemSettingsNames {
    let privacy = extensions.appending(path: "SecurityPrivacyExtension.appex", directoryHint: .isDirectory)
    let notifications = extensions.appending(path: "NotificationsSettings.appex", directoryHint: .isDirectory)
    let privacyNames = table("InfoPlist", of: privacy, languages: languages)
    let panes = table("Localizable", of: privacy, languages: languages)
    let notificationsNames = table("InfoPlist", of: notifications, languages: languages)
    let notificationsPane = table("Localizable", of: notifications, languages: languages)
    return SystemSettingsNames(
      privacyAndSecurity: privacyNames["CFBundleDisplayName"] as? String,
      accessibility: panes["ACCESSIBILITY"] as? String,
      // macOS 15 renamed the pane and kept the old name's key.
      screenRecording: (panes["SCREENANDAUDIOCAPTURE"] ?? panes["SCREEN_CAPTURE"]) as? String,
      pasteFromOtherApps: panes["PASTEBOARD_ACCESS"] as? String,
      notifications: notificationsNames["CFBundleDisplayName"] as? String,
      allowNotifications: notificationsPane["Allow notifications"] as? String
    )
  }

  /// One table of an extension in the language System Settings picks from `languages`; empty when there is none.
  static func table(_ name: String, of appex: URL, languages: [String]) -> [String: Any] {
    let resources = appex.appending(path: "Contents/Resources", directoryHint: .isDirectory)
    if let all = plist(resources.appending(path: "\(name).loctable")) as? [String: Any] {
      let available = all.keys.filter { $0 != "LocProvenance" }
      guard let language = Bundle.preferredLocalizations(from: available, forPreferences: languages).first else { return [:] }
      return all[language] as? [String: Any] ?? [:]
    }
    let available = ((try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? [])
      .filter { $0.hasSuffix(".lproj") }
      .map { String($0.dropLast(".lproj".count)) }
    guard let language = Bundle.preferredLocalizations(from: available, forPreferences: languages).first else { return [:] }
    return plist(resources.appending(path: "\(language).lproj/\(name).strings")) as? [String: Any] ?? [:]
  }

  private static func plist(_ url: URL) -> Any? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? PropertyListSerialization.propertyList(from: data, format: nil)
  }
}
