import ComposableArchitecture
import Foundation

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
  /// Add one to make the notch flash once, e.g. when a new file lands on the shelf. Only growth counts:
  /// an indicator that is removed and comes back with the same number does not flash.
  public var flash: Int
  /// The color of that flash: a glow around the notch that spreads past its edges.
  public var flashColor: ColorValue

  /// An indicator with no items shows no ears; it can still flash the notch.
  public init(leading: [Item], trailing: [Item], priority: Int = 0, flash: Int = 0, flashColor: ColorValue = .white) {
    self.leading = leading
    self.trailing = trailing
    self.priority = priority
    self.flash = flash
    self.flashColor = flashColor
  }
}

/// How indicators are laid out around the notch.
///
/// One indicator: its leading items go left of the cutout, trailing items right.
/// Two or more: the highest priority fills the left ear, the next one the right ear; the rest wait.
public struct NotchEars: Equatable, Sendable {
  public var left: [NotchIndicator.Item]
  public var right: [NotchIndicator.Item]
  /// The features whose indicators fill the ears; a hover or a click on an ear opens its feature.
  public var leftFeature: FeatureID?
  public var rightFeature: FeatureID?

  public var isEmpty: Bool { left.isEmpty && right.isEmpty }

  public init(
    left: [NotchIndicator.Item] = [],
    right: [NotchIndicator.Item] = [],
    leftFeature: FeatureID? = nil,
    rightFeature: FeatureID? = nil
  ) {
    self.left = left
    self.right = right
    self.leftFeature = leftFeature
    self.rightFeature = rightFeature
  }

  public init(indicators: [FeatureID: NotchIndicator]) {
    let ranked = indicators
      .filter { !$0.value.leading.isEmpty || !$0.value.trailing.isEmpty }
      .sorted { $0.value.priority != $1.value.priority ? $0.value.priority > $1.value.priority : $0.key < $1.key }
    switch ranked.count {
    case 0:
      self.init()
    case 1:
      let (id, indicator) = ranked[0]
      self.init(left: indicator.leading, right: indicator.trailing, leftFeature: id, rightFeature: id)
    default:
      let (first, second) = (ranked[0], ranked[1])
      self.init(
        left: first.value.leading + first.value.trailing,
        right: second.value.leading + second.value.trailing,
        leftFeature: first.key,
        rightFeature: second.key
      )
    }
  }

  /// The feature whose ear is at `x`, in a view `width` wide with the cutout in the middle; nil on the cutout itself.
  public func feature(atX x: CGFloat, width: CGFloat, notchWidth: CGFloat) -> FeatureID? {
    let side = (width - notchWidth) / 2
    if x < side { return leftFeature }
    if x > width - side { return rightFeature }
    return nil
  }

  /// The color to flash in when some indicator's `flash` grew past the number last seen for its feature; nil when
  /// none did. `seen` keeps the numbers of removed indicators too, so one that comes back with an old number does not
  /// flash.
  public static func flash(_ indicators: [FeatureID: NotchIndicator], seen: inout [FeatureID: Int]) -> ColorValue? {
    var color: ColorValue?
    for (id, indicator) in indicators.sorted(by: { $0.key < $1.key }) {
      if color == nil, indicator.flash > seen[id, default: 0] {
        color = indicator.flashColor
      }
      seen[id] = indicator.flash
    }
    return color
  }

  /// Text for the menu bar icon on displays without a notch, e.g. "8:42  2".
  public var menuBarText: String {
    (left + right).compactMap { item in
      if case let .text(text) = item { text } else { nil }
    }
    .joined(separator: "  ")
  }
}

extension SharedReaderKey where Self == InMemoryKey<[FeatureID: NotchIndicator]>.Default {
  /// What features show in the closed notch, keyed by feature id. A feature writes only its own entry,
  /// from its reducer: `state.$indicators.withLock { $0[Self.id] = indicator }`; `nil` removes it.
  public static var notchIndicators: Self {
    Self[.inMemory("notchIndicators"), default: [:]]
  }
}
