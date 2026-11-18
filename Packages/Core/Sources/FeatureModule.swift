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
  /// where the tab's own drop target receives them; files dropped on the menu bar icon (never on macOS 26, where the
  /// drop doesn't reach Vortex) or opened with Vortex (`vortex shelf add`) arrive in `receiveFiles(_:)`. The first
  /// enabled feature that accepts files gets them.
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

  // MARK: The catalog's description. Plain data: the shell reads it without running the feature.

  /// One line on the feature's card in the catalog and in the onboarding.
  static var summary: LocalizedStringResource { get }
  /// Two to four lines on the feature's page in the catalog.
  static var details: LocalizedStringResource { get }
  /// Who made the feature, as a name or a GitHub handle.
  static var author: String { get }
  /// Most people need it: added on a fresh install and marked "Recommended". Only the maintainer sets it.
  static var isRecommended: Bool { get }
  /// New and may still change: marked "Beta" in the catalog.
  static var isBeta: Bool { get }
  /// Always added and running, never in the catalog or the onboarding, never stopped after a crash: Home.
  static var isBuiltIn: Bool { get }
  /// Set by the maintainer for a release in which the feature must not run, with the reason the catalog shows.
  static var suspension: LocalizedStringResource? { get }
  /// What the feature keeps, in one line, for "Erase Data"; nil when it keeps nothing.
  static var keeps: LocalizedStringResource? { get }
  /// What erasing does beyond the feature's own data, said before the user confirms, such as keys leaving the keychain;
  /// nil when there is nothing more.
  static var eraseNote: LocalizedStringResource? { get }
  /// The feature's folder in `DataFolder`, which "Erase Data" deletes; nil when it has none.
  static var dataFolder: String? { get }
  /// Whether `makeOnboardingStep()` returns a step, known without calling it.
  static var hasOnboardingStep: Bool { get }
  /// The looping video and the still on the feature's page; nil shows its symbol instead.
  static var preview: FeaturePreview? { get }
  /// Erases what only the feature knows about, such as keychain items or its own shortcuts. The shell erases its
  /// tables, migrations, settings file and folder itself. Called only for a feature that isn't added, on a launch
  /// before anything starts.
  static func eraseData() async
}

extension FeatureModule {
  public static var acceptsFileDrops: Bool { false }
  public static func makeSettings() -> AnyView? { nil }
  public static func makeHomeWidget() -> HomeWidget? { nil }
  public static func setEnabled(_ isEnabled: Bool) {}
  public static func receiveFiles(_ urls: [URL]) {}
  public static var permissionNeeds: [PermissionNeed] { [] }
  public static func makeOnboardingStep() -> OnboardingStep? { nil }
  public static var isRecommended: Bool { false }
  public static var isBeta: Bool { false }
  public static var isBuiltIn: Bool { false }
  public static var suspension: LocalizedStringResource? { nil }
  public static var keeps: LocalizedStringResource? { nil }
  public static var eraseNote: LocalizedStringResource? { nil }
  public static var dataFolder: String? { nil }
  public static var hasOnboardingStep: Bool { false }
  public static var preview: FeaturePreview? { nil }
  public static func eraseData() async {}

  /// Plain description of the feature for the shell's state.
  public static var descriptor: FeatureDescriptor {
    FeatureDescriptor(
      id: id,
      title: title,
      symbol: symbol,
      acceptsFileDrops: acceptsFileDrops,
      permissionNeeds: permissionNeeds,
      summary: summary,
      details: details,
      author: author,
      isRecommended: isRecommended,
      isBeta: isBeta,
      isBuiltIn: isBuiltIn,
      suspension: suspension,
      keeps: keeps,
      eraseNote: eraseNote,
      dataFolder: dataFolder,
      hasOnboardingStep: hasOnboardingStep,
      preview: preview
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
  /// The fields below: see the `FeatureModule` requirements of the same names.
  public var summary: LocalizedStringResource
  public var details: LocalizedStringResource
  public var author: String
  public var isRecommended: Bool
  public var isBeta: Bool
  public var isBuiltIn: Bool
  public var suspension: LocalizedStringResource?
  public var keeps: LocalizedStringResource?
  public var eraseNote: LocalizedStringResource?
  public var dataFolder: String?
  public var hasOnboardingStep: Bool
  public var preview: FeaturePreview?

  public init(
    id: FeatureID,
    title: LocalizedStringResource,
    symbol: String,
    acceptsFileDrops: Bool = false,
    permissionNeeds: [PermissionNeed] = [],
    summary: LocalizedStringResource = "",
    details: LocalizedStringResource = "",
    author: String = "",
    isRecommended: Bool = false,
    isBeta: Bool = false,
    isBuiltIn: Bool = false,
    suspension: LocalizedStringResource? = nil,
    keeps: LocalizedStringResource? = nil,
    eraseNote: LocalizedStringResource? = nil,
    dataFolder: String? = nil,
    hasOnboardingStep: Bool = false,
    preview: FeaturePreview? = nil
  ) {
    self.id = id
    self.title = title
    self.symbol = symbol
    self.acceptsFileDrops = acceptsFileDrops
    self.permissionNeeds = permissionNeeds
    self.summary = summary
    self.details = details
    self.author = author
    self.isRecommended = isRecommended
    self.isBeta = isBeta
    self.isBuiltIn = isBuiltIn
    self.suspension = suspension
    self.keeps = keeps
    self.eraseNote = eraseNote
    self.dataFolder = dataFolder
    self.hasOnboardingStep = hasOnboardingStep
    self.preview = preview
  }
}
