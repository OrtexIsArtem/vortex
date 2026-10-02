import Foundation

/// The contract every feature implements to plug into the app shell.
///
/// The shell (sidebar, settings, Home, notch indicators) knows features only through this protocol.
/// Stage 1 extends it with the sidebar tab, the Home widget, settings and the notch indicator.
public protocol FeatureModule {
  /// Stable identifier. Also the prefix of the feature's database tables.
  static var id: String { get }
  /// Name shown in the sidebar tooltip and in settings.
  static var title: LocalizedStringResource { get }
  /// SF Symbol shown in the sidebar.
  static var symbol: String { get }
}
