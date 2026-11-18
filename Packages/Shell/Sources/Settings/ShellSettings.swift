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
  /// Features whose data the next launch erases before anything starts.
  var pendingErase: [FeatureID] = []
  /// False on a fresh install until the user leaves the onboarding's Features page or closes the onboarding:
  /// until then only built-in features run.
  var featuresChosen = true
  /// The tab to open next time, see `ShellFeature.Tab.storageValue`.
  var lastTab: String?

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
    pendingErase = value(.pendingErase, defaults.pendingErase)
    featuresChosen = value(.featuresChosen, defaults.featuresChosen)
    lastTab = value(.lastTab, defaults.lastTab)
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

  static func clampedDelay(_ delay: Double) -> Double {
    guard delay.isFinite else { return delayRange.lowerBound }
    return min(max(delay, delayRange.lowerBound), delayRange.upperBound)
  }
}
