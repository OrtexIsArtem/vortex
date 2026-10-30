import SwiftUI

/// Stable identifier of a feature: used in settings, for the sidebar order and as the prefix of its database tables.
public typealias FeatureID = String

/// The contract every feature implements to plug into the app shell.
///
/// The shell (sidebar, settings, notch) knows features only through this protocol and never imports a feature
/// module directly. A feature keeps one store for the life of the app; the shell only asks it for views.
@MainActor
public protocol FeatureModule {
  /// Stable identifier. Also the prefix of the feature's database tables.
  static var id: FeatureID { get }
  /// Name shown in the sidebar tooltip and in settings. Build it from the feature's own bundle, so it gets
  /// translated: `LocalizedStringResource("Clipboard", bundle: .atURL(Bundle.module.bundleURL))`.
  static var title: LocalizedStringResource { get }
  /// SF Symbol shown in the sidebar.
  static var symbol: String { get }
  /// Whether files given to Vortex belong to this feature. Files dragged to the notch open the window on its tab,
  /// where the tab's own drop target receives them; files dropped on the menu bar icon or opened with Vortex
  /// (`vortex shelf add`) arrive in `receiveFiles(_:)`. The first enabled feature that accepts files gets them.
  static var acceptsFileDrops: Bool { get }
  /// Content of the feature's sidebar tab. It stays mounted while the window is closed, so work that should
  /// run only while it is visible goes into `.task(id: isWindowOpen)`.
  static func makeTab() -> AnyView
  /// The feature's own section in Settings › Features, if it has settings.
  static func makeSettings() -> AnyView?
  /// The feature's widget on Home, if it has one; see `HomeSlot`.
  static func makeHomeWidget() -> HomeWidget?
  /// Called at launch and whenever the user turns the feature on or off. Start and stop background work here.
  static func setEnabled(_ isEnabled: Bool)
  /// Files given to Vortex outside the feature's tab, see `acceptsFileDrops`. The window stays as it is.
  static func receiveFiles(_ urls: [URL])
  /// The macOS permissions the feature needs, each with the reason the user reads next to it. While the
  /// feature is on, the onboarding asks for them; the feature itself never asks macOS, it opens the shell's page with
  /// `@Dependency(\.permissionPage)`.
  static var permissionNeeds: [PermissionNeed] { get }
  /// The feature's own page in the onboarding, after the permission pages, if it has one.
  static func makeOnboardingStep() -> OnboardingStep?
}

extension FeatureModule {
  public static var acceptsFileDrops: Bool { false }
  public static func makeSettings() -> AnyView? { nil }
  public static func makeHomeWidget() -> HomeWidget? { nil }
  public static func setEnabled(_ isEnabled: Bool) {}
  public static func receiveFiles(_ urls: [URL]) {}
  public static var permissionNeeds: [PermissionNeed] { [] }
  public static func makeOnboardingStep() -> OnboardingStep? { nil }

  /// Plain description of the feature for the shell's state.
  public static var descriptor: FeatureDescriptor {
    FeatureDescriptor(
      id: id,
      title: title,
      symbol: symbol,
      acceptsFileDrops: acceptsFileDrops,
      permissionNeeds: permissionNeeds
    )
  }
}

/// Plain description of a feature, safe to keep in reducer state.
public struct FeatureDescriptor: Equatable, Identifiable, Sendable {
  public var id: FeatureID
  public var title: LocalizedStringResource
  public var symbol: String
  public var acceptsFileDrops: Bool
  /// See `FeatureModule.permissionNeeds`.
  public var permissionNeeds: [PermissionNeed]

  public init(
    id: FeatureID,
    title: LocalizedStringResource,
    symbol: String,
    acceptsFileDrops: Bool = false,
    permissionNeeds: [PermissionNeed] = []
  ) {
    self.id = id
    self.title = title
    self.symbol = symbol
    self.acceptsFileDrops = acceptsFileDrops
    self.permissionNeeds = permissionNeeds
  }
}
