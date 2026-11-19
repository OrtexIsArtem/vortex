import Foundation
import VortexCore

/// Everything the user sets for the shell.
///
/// Stored as JSON. Missing or unreadable keys fall back to their defaults, so the file
/// keeps working when settings are added, removed or renamed between versions.
struct ShellSettings: Codable, Equatable, Sendable {
  static let delayRange: ClosedRange<Double> = 0...2

  var openOnHover = true
  var hoverDelay: Double = 0.3
  var openOnClick = true
  var closeOnClickOutside = true
  var closeOnPointerLeave = true
  var pointerLeaveDelay: Double = 0.5
  var showMenuBarIcon = true
  var theme: AppTheme = .system
  /// Feature ids in the user's order. Features missing here follow in registry order.
  var featureOrder: [FeatureID] = []
  /// Read once, from a settings file written before the catalog, to fill `addedFeatures`; empty after that.
  var disabledFeatures: [FeatureID] = []
  /// The features the user added, built-in ones included. Nil until settled at launch, see `settleAddedFeatures`.
  var addedFeatures: [FeatureID]?
  /// The features the catalog has shown; one missing here is new.
  var seenFeatures: [FeatureID] = []
  /// Features stopped after Vortex crashed while starting them; they stay added and wait for Try Again.
  var stoppedFeatures: [FeatureID] = []
  /// The build that stopped them, `AppVersion.full`: another build forgets them, as it may have fixed the crash.
  var stoppedInVersion: String?
  /// Features whose data the next launch erases before anything starts.
  var pendingErase: [FeatureID] = []
  /// False on a fresh install until the user leaves the onboarding's Features page or closes the onboarding:
  /// until then only built-in features run.
  var featuresChosen = true
  /// The tab to open next time, see `ShellFeature.Tab.storageValue`.
  var lastTab: String?
  /// The one-time changes to the saved features made already, by name (`Self.featureMigrations`).
  var migrations: [String] = []

  /// One-time changes to the saved features, each made at the first launch of a build that ships its feature: a part of
  /// Vortex that becomes a feature of its own stays added for whoever had it, as keyboard cleaning, which Home brought,
  /// became a utility.
  static let featureMigrations: [(name: String, keepsAdded: FeatureID)] = [("keyboard.added", "keyboard")]

  init() {}

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = ShellSettings()
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    openOnHover = value(.openOnHover, defaults.openOnHover)
    hoverDelay = Self.clampedDelay(value(.hoverDelay, defaults.hoverDelay))
    openOnClick = value(.openOnClick, defaults.openOnClick)
    closeOnClickOutside = value(.closeOnClickOutside, defaults.closeOnClickOutside)
    closeOnPointerLeave = value(.closeOnPointerLeave, defaults.closeOnPointerLeave)
    pointerLeaveDelay = Self.clampedDelay(value(.pointerLeaveDelay, defaults.pointerLeaveDelay))
    showMenuBarIcon = value(.showMenuBarIcon, defaults.showMenuBarIcon)
    theme = value(.theme, defaults.theme)
    featureOrder = value(.featureOrder, defaults.featureOrder)
    disabledFeatures = value(.disabledFeatures, defaults.disabledFeatures)
    addedFeatures = value(.addedFeatures, defaults.addedFeatures)
    seenFeatures = value(.seenFeatures, defaults.seenFeatures)
    stoppedFeatures = value(.stoppedFeatures, defaults.stoppedFeatures)
    stoppedInVersion = value(.stoppedInVersion, defaults.stoppedInVersion)
    pendingErase = value(.pendingErase, defaults.pendingErase)
    featuresChosen = value(.featuresChosen, defaults.featuresChosen)
    lastTab = value(.lastTab, defaults.lastTab)
    migrations = value(.migrations, defaults.migrations)
  }

  /// Fills `addedFeatures` once. A fresh install gets the recommended and built-in features, not yet chosen; settings
  /// from a release before the catalog keep every feature that wasn't turned off. Either way the catalog counts all of
  /// today's features as seen, so none of them is marked new.
  mutating func settleAddedFeatures(all: [FeatureDescriptor], isFreshInstall: Bool) {
    guard addedFeatures == nil else { return }
    if isFreshInstall {
      addedFeatures = all.filter { $0.isRecommended || $0.isBuiltIn }.map(\.id)
      featuresChosen = false
    } else {
      addedFeatures = all.filter { $0.isBuiltIn || !disabledFeatures.contains($0.id) }.map(\.id)
      disabledFeatures = []
    }
    seenFeatures = all.map(\.id)
  }

  /// What a launch does with the loaded settings before anything starts: settles the added features and applies how the
  /// last launch ended. True when the result must be written at once: settled for the first time (else an unclean quit
  /// before the first save would bring back settings that look like an update's), or a feature stopped.
  mutating func prepareLaunch(all: [FeatureDescriptor], isFreshInstall: Bool, verdict: LaunchVerdict, version: String) -> Bool {
    let wasSettled = addedFeatures != nil
    let stoppedBefore = stoppedFeatures
    settleAddedFeatures(all: all, isFreshInstall: isFreshInstall)
    let migrated = migrateFeatures(all: all, wasSettled: wasSettled)
    applyLaunch(verdict, version: version)
    return !wasSettled || migrated || stoppedFeatures != stoppedBefore
  }

  /// Makes the one-time changes this build ships the features of and hasn't made yet (`featureMigrations`): settings
  /// settled before this launch keep the feature added and seen, so it is no news in the catalog; settings settled now
  /// already have what they should. True when one was made.
  mutating func migrateFeatures(all: [FeatureDescriptor], wasSettled: Bool) -> Bool {
    let ids = all.map(\.id)
    var changed = false
    for migration in Self.featureMigrations where !migrations.contains(migration.name) && ids.contains(migration.keepsAdded) {
      migrations.append(migration.name)
      changed = true
      guard wasSettled, var added = addedFeatures else { continue }
      if !added.contains(migration.keepsAdded) { added.append(migration.keepsAdded) }
      // In the registry's order, as adding keeps it; ids of features this build lacks stay at the end.
      addedFeatures = ids.filter(added.contains) + added.filter { !ids.contains($0) }
      if !seenFeatures.contains(migration.keepsAdded) { seenFeatures.append(migration.keepsAdded) }
    }
    return changed
  }

  /// Applies how the last launch ended, at launch: a crash blamed on a feature stops it until Try Again. A build other
  /// than the one that stopped features forgets them first, as it may have fixed the crash.
  mutating func applyLaunch(_ verdict: LaunchVerdict, version: String) {
    if stoppedInVersion != version {
      stoppedFeatures = []
      stoppedInVersion = nil
    }
    guard case let .stop(id) = verdict, !stoppedFeatures.contains(id) else { return }
    stoppedFeatures.append(id)
    stoppedInVersion = version
  }

  static func clampedDelay(_ delay: Double) -> Double {
    guard delay.isFinite else { return delayRange.lowerBound }
    return min(max(delay, delayRange.lowerBound), delayRange.upperBound)
  }
}
