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
  var disabledFeatures: [FeatureID] = []
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
    lastTab = value(.lastTab, defaults.lastTab)
  }

  static func clampedDelay(_ delay: Double) -> Double {
    guard delay.isFinite else { return delayRange.lowerBound }
    return min(max(delay, delayRange.lowerBound), delayRange.upperBound)
  }
}
