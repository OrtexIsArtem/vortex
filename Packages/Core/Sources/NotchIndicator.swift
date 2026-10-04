import ComposableArchitecture

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
  /// Change it (add one) to make the notch flash once, e.g. when a new file lands on the shelf.
  public var flash: Int

  public init(leading: [Item], trailing: [Item], priority: Int = 0, flash: Int = 0) {
    self.leading = leading
    self.trailing = trailing
    self.priority = priority
    self.flash = flash
  }
}

/// How indicators are laid out around the notch.
///
/// One indicator: its leading items go left of the cutout, trailing items right.
/// Two or more: the highest priority fills the left ear, the next one the right ear; the rest wait.
public struct NotchEars: Equatable, Sendable {
  public var left: [NotchIndicator.Item]
  public var right: [NotchIndicator.Item]
  /// Changes whenever some indicator asks for a flash.
  public var flash: Int

  public var isEmpty: Bool { left.isEmpty && right.isEmpty }

  public init(left: [NotchIndicator.Item] = [], right: [NotchIndicator.Item] = [], flash: Int = 0) {
    self.left = left
    self.right = right
    self.flash = flash
  }

  public init(indicators: [FeatureID: NotchIndicator]) {
    let ranked = indicators
      .sorted { $0.value.priority != $1.value.priority ? $0.value.priority > $1.value.priority : $0.key < $1.key }
      .map(\.value)
    let flash = ranked.reduce(0) { $0 &+ $1.flash }
    switch ranked.count {
    case 0:
      self.init()
    case 1:
      self.init(left: ranked[0].leading, right: ranked[0].trailing, flash: flash)
    default:
      self.init(left: ranked[0].leading + ranked[0].trailing, right: ranked[1].leading + ranked[1].trailing, flash: flash)
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

extension SharedReaderKey where Self == InMemoryKey<[FeatureID: NotchIndicator]>.Default {
  /// What features show in the closed notch, keyed by feature id. A feature writes only its own entry,
  /// from its reducer: `state.$indicators.withLock { $0[Self.id] = indicator }`; `nil` removes it.
  public static var notchIndicators: Self {
    Self[.inMemory("notchIndicators"), default: [:]]
  }
}
