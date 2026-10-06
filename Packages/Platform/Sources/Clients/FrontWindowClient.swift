import AppKit
import ComposableArchitecture

/// The app the user is working in: its front window's title and, for a browser, the address of the open page.
public struct FrontWindow: Codable, Equatable, Sendable {
  public var app: AppInfo?
  public var windowTitle: String?
  public var url: URL?

  public init(app: AppInfo? = nil, windowTitle: String? = nil, url: URL? = nil) {
    self.app = app
    self.windowTitle = windowTitle
    self.url = url
  }

  /// Titles carry invisible direction marks (Telegram wraps chat names in them) and stray spaces: both go.
  public static func cleanTitle(_ title: String?) -> String? {
    let invisible: Set<Unicode.Scalar> = ["\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
                                          "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}", "\u{FEFF}"]
    guard let title else { return nil }
    var scalars = String.UnicodeScalarView()
    scalars.append(contentsOf: title.unicodeScalars.filter { !invisible.contains($0) })
    let cleaned = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? nil : cleaned
  }
}

/// The app in front and what is open in it. Vortex's own panels never take the front, so this is the app the user
/// was in when they pressed a shortcut. The window title needs the Screen Recording permission; the page address
/// needs Automation of that browser, which macOS asks for once per browser.
@DependencyClient
public struct FrontWindowClient: Sendable {
  /// Each part is nil when it can't be known.
  public var current: @Sendable () async -> FrontWindow = { FrontWindow() }
}

extension FrontWindowClient: DependencyKey {
  public static let liveValue = FrontWindowClient(
    current: {
      let front = await MainActor.run { () -> (AppInfo, pid_t)? in
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier
        else { return nil }
        return (AppInfo(bundleID: id, name: app.localizedName ?? id), app.processIdentifier)
      }
      guard let front else { return FrontWindow() }
      let (app, pid) = front
      return FrontWindow(app: app, windowTitle: windowTitle(of: pid), url: await BrowserPage.url(in: app.bundleID))
    }
  )

  public static let testValue = FrontWindowClient()

  /// The title of the app's frontmost window on screen.
  private static func windowTitle(of pid: pid_t) -> String? {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] ?? []
    // Front to back: the first ordinary window of the app with a title.
    let title = windows.lazy
      .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
      .compactMap { FrontWindow.cleanTitle($0[kCGWindowName as String] as? String) }
      .first
    return title
  }
}

extension DependencyValues {
  public var frontWindowClient: FrontWindowClient {
    get { self[FrontWindowClient.self] }
    set { self[FrontWindowClient.self] = newValue }
  }
}

/// The address of the page open in a browser, through AppleScript. Firefox has no such scripting.
enum BrowserPage {
  private static let chromium: Set<String> = [
    "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
    "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
    "com.operasoftware.Opera",
  ]
  private static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
  /// AppleScript is used from this one thread, never two at a time.
  private static let queue = DispatchQueue(label: "io.github.ortexisartem.vortex.browser-page")

  static func url(in bundleID: String) async -> URL? {
    let command: String
    if chromium.contains(bundleID) {
      command = "get URL of active tab of front window"
    } else if safari.contains(bundleID) {
      command = "get URL of front document"
    } else {
      return nil
    }
    // A browser that hangs, or a permission prompt left open, must not hold the capture for long.
    let source = """
      with timeout of 3 seconds
        tell application id "\(bundleID)" to \(command)
      end timeout
      """
    return await withCheckedContinuation { continuation in
      queue.async {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
        continuation.resume(returning: result.flatMap(URL.init(string:)).flatMap { $0.scheme == nil ? nil : $0 })
      }
    }
  }
}
