import Dependencies
import Observation

/// What a feature shows in the closed notch: small "ears" on both sides of the cutout.
public struct NotchIndicator: Equatable, Sendable {
  public enum Item: Equatable, Sendable {
    /// SF Symbol name.
    case symbol(String)
    /// Short text such as "8:42" or "2".
    case text(String)
    /// Progress ring, 0…1.
    case progress(Double)
  }

  public var leading: [Item]
  public var trailing: [Item]
  /// Higher priority wins the left ear when several features show something.
  public var priority: Int

  public init(leading: [Item], trailing: [Item], priority: Int = 0) {
    self.leading = leading
    self.trailing = trailing
    self.priority = priority
  }
}

/// How indicators are laid out around the notch.
///
/// One indicator: its leading items go left of the cutout, trailing items right.
/// Two or more: the highest priority fills the left ear, the next one the right ear; the rest wait.
public struct NotchEars: Equatable, Sendable {
  public var left: [NotchIndicator.Item]
  public var right: [NotchIndicator.Item]

  public var isEmpty: Bool { left.isEmpty && right.isEmpty }

  public init(left: [NotchIndicator.Item] = [], right: [NotchIndicator.Item] = []) {
    self.left = left
    self.right = right
  }

  public init(indicators: [FeatureID: NotchIndicator]) {
    let ranked = indicators
      .sorted { $0.value.priority != $1.value.priority ? $0.value.priority > $1.value.priority : $0.key < $1.key }
      .map(\.value)
    switch ranked.count {
    case 0:
      self.init()
    case 1:
      self.init(left: ranked[0].leading, right: ranked[0].trailing)
    default:
      self.init(left: ranked[0].leading + ranked[0].trailing, right: ranked[1].leading + ranked[1].trailing)
    }
  }

  /// Text for the menu bar icon on displays without a notch, e.g. "8:42  2".
  public var menuBarText: String {
    (left + right).compactMap { item in
      if case let .text(text) = item { text } else { nil }
    }
    .joined(separator: "  ")
  }
}

/// Indicators that features publish for the closed notch. The shell reads them; features write their own.
@MainActor
@Observable
public final class NotchIndicatorCenter {
  public private(set) var indicators: [FeatureID: NotchIndicator] = [:]

  public nonisolated init() {}

  public var ears: NotchEars { NotchEars(indicators: indicators) }

  /// Shows, updates or (with `nil`) removes the indicator of a feature.
  public func set(_ indicator: NotchIndicator?, for feature: FeatureID) {
    indicators[feature] = indicator
  }
}

extension NotchIndicatorCenter: DependencyKey {
  public nonisolated static let liveValue = NotchIndicatorCenter()
  public nonisolated static var testValue: NotchIndicatorCenter { NotchIndicatorCenter() }
}

extension DependencyValues {
  public var notchIndicators: NotchIndicatorCenter {
    get { self[NotchIndicatorCenter.self] }
    set { self[NotchIndicatorCenter.self] = newValue }
  }
}
