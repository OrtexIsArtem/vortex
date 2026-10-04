import AppKit
import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

/// Other apps on this Mac.
@DependencyClient
public struct AppsClient: Sendable {
  /// Apps with a Dock icon that are running now, sorted by name.
  public var running: @Sendable () async -> [AppInfo] = { [] }
}

extension AppsClient: DependencyKey {
  public static let liveValue = AppsClient(
    running: {
      await MainActor.run {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
          .filter { $0.activationPolicy == .regular }
          .compactMap { app -> AppInfo? in
            guard let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
            return AppInfo(bundleID: id, name: app.localizedName ?? id)
          }
          .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
