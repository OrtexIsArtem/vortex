import FeatureClipboard
import FeatureShelf
import FeatureTimer
import VortexCore

/// Every feature the app ships with, in default sidebar order.
///
/// One import and one line per feature. Removing a feature: delete its folder, its import and line here
/// and its name in `features` in Packages/Package.swift.
@MainActor
public enum FeatureRegistry {
  public static let all: [any FeatureModule.Type] = [
    TimerModule.self,
    ClipboardModule.self,
    ShelfModule.self,
  ]

  public static func module(for id: FeatureID) -> (any FeatureModule.Type)? {
    all.first { $0.id == id }
  }
}
