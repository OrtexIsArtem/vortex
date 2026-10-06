import SwiftUI

/// Where a feature's widget sits on Home (variant B «Вуха» of the design).
public enum HomeSlot: Sendable {
  /// The row next to the notch. Home shows one: the first such widget in sidebar order.
  case header
  /// The middle of Home, top to bottom in sidebar order.
  case main
  /// The dock at the bottom, side by side in sidebar order; each widget picks its own width.
  case dock
}

/// A feature's part of Home. The shell collects them from enabled features and hands them to Home in
/// `homeWidgets`; Home never knows the features themselves.
public struct HomeWidget: Identifiable {
  public let id: FeatureID
  public let slot: HomeSlot
  public let view: AnyView

  @MainActor
  public init(id: FeatureID, slot: HomeSlot, view: some View) {
    self.id = id
    self.slot = slot
    self.view = AnyView(view)
  }
}

extension EnvironmentValues {
  /// Widgets of the enabled features, in sidebar order, for Home.
  @Entry public var homeWidgets: [HomeWidget] = []
}
