import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers
import VortexCore

/// Other apps on this Mac.
@DependencyClient
public struct AppsClient: Sendable {
  /// Apps running now, with a Dock icon or in the menu bar, sorted by name; Vortex itself is left out.
  public var running: @Sendable () async -> [AppInfo] = { [] }
  /// Asks the user to pick an app in /Applications; nil when they cancel.
  public var choose: @Sendable () async -> AppInfo?
}

extension AppsClient: DependencyKey {
  public static let liveValue = AppsClient(
    running: {
      await MainActor.run {
        var seen: Set<String> = [Bundle.main.bundleIdentifier ?? ""]
        return NSWorkspace.shared.runningApplications
          .filter { $0.activationPolicy != .prohibited }
          .compactMap { app -> AppInfo? in
            guard let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return AppInfo(bundleID: id, name: app.localizedName ?? id)
          }
          .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
      }
    },
    choose: {
      await withCheckedContinuation { continuation in
        Task { @MainActor in
          let panel = NSOpenPanel()
          panel.allowedContentTypes = [.application]
          panel.directoryURL = URL(fileURLWithPath: "/Applications")
          panel.allowsMultipleSelection = false
          // Vortex has no Dock icon and its window floats above the menu bar: lift the panel over it.
          panel.level = .aboveVortex
          NSApp.activate()
          OutsideActivity.shared.begin()
          panel.begin { response in
            OutsideActivity.shared.end()
            guard response == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else {
              continuation.resume(returning: nil)
              return
            }
            let name = FileManager.default.displayName(atPath: url.path)
            continuation.resume(returning: AppInfo(bundleID: id, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name))
          }
        }
      }
    }
  )

  public static let testValue = AppsClient()
}

extension DependencyValues {
  public var appsClient: AppsClient {
    get { self[AppsClient.self] }
    set { self[AppsClient.self] = newValue }
  }
}

/// The icon of an app; a generic app icon when it is not installed.
public struct AppIcon: View {
  private let bundleID: String

  public init(bundleID: String) {
    self.bundleID = bundleID
  }

  public var body: some View {
    Image(nsImage: AppIconCache.icon(for: bundleID))
      .resizable()
      .interpolation(.high)
      .aspectRatio(contentMode: .fit)
      .accessibilityHidden(true)
  }
}

@MainActor
private enum AppIconCache {
  static var icons: [String: NSImage] = [:]

  static func icon(for bundleID: String) -> NSImage {
    if let icon = icons[bundleID] { return icon }
    let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
      .map { NSWorkspace.shared.icon(forFile: $0.path) }
      ?? NSWorkspace.shared.icon(for: .application)
    icons[bundleID] = icon
    return icon
  }
}
