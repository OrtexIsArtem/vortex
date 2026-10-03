import SwiftUI

/// Stable identifier of a feature: used in settings, for the sidebar order and as the prefix of its database tables.
public typealias FeatureID = String

/// The contract every feature implements to plug into the app shell.
///
/// The shell (sidebar, settings, notch indicators) knows features only through this protocol and never
/// imports a feature module directly. A feature keeps its own store; the shell only asks it for views.
@MainActor
public protocol FeatureModule {
  /// Stable identifier. Also the prefix of the feature's database tables.
  static var id: FeatureID { get }
  /// Name shown in the sidebar tooltip and in settings.
  static var title: LocalizedStringResource { get }
  /// SF Symbol shown in the sidebar.
  static var symbol: String { get }
  /// Whether files dragged to the notch or dropped on the menu bar icon belong to this feature.
  static var acceptsFileDrops: Bool { get }
  /// Content of the feature's sidebar tab.
  static func makeTab() -> AnyView
  /// The feature's own section in Settings › Features, if it has settings.
  static func makeSettings() -> AnyView?
}

extension FeatureModule {
  public static var acceptsFileDrops: Bool { false }
  public static func makeSettings() -> AnyView? { nil }

  /// Plain description of the feature for the shell's state.
  public static var descriptor: FeatureDescriptor {
    FeatureDescriptor(id: id, title: title, symbol: symbol, acceptsFileDrops: acceptsFileDrops)
  }
}

/// Plain description of a feature, safe to keep in reducer state.
public struct FeatureDescriptor: Equatable, Identifiable, Sendable {
  public var id: FeatureID
  public var title: LocalizedStringResource
  public var symbol: String
  public var acceptsFileDrops: Bool

  public init(id: FeatureID, title: LocalizedStringResource, symbol: String, acceptsFileDrops: Bool = false) {
    self.id = id
    self.title = title
    self.symbol = symbol
    self.acceptsFileDrops = acceptsFileDrops
  }
}
