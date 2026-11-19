import Foundation
import SwiftUI
import Testing

@testable import VortexCore

/// A feature that fills in every catalog field.
@MainActor
private enum SampleModule: FeatureModule {
  static let id: FeatureID = "sample"
  static let title: LocalizedStringResource = "Sample"
  static let symbol = "square"
  static let summary: LocalizedStringResource = "One line for the card"
  static let details: LocalizedStringResource = "A few lines for the page"
  static let author = "@someone"
  static let isRecommended = true
  static let isBeta = true
  static let suspension: LocalizedStringResource? = "Paused until the next release"
  static let keeps: LocalizedStringResource? = "Its own things"
  static let dataFolder: String? = "Sample"
  static let hasOnboardingStep = true

  static func makeTab() -> AnyView { AnyView(EmptyView()) }
}

/// A feature that declares only what it must.
@MainActor
private enum PlainModule: FeatureModule {
  static let id: FeatureID = "plain"
  static let title: LocalizedStringResource = "Plain"
  static let symbol = "circle"
  static let summary: LocalizedStringResource = "Plain"
  static let details: LocalizedStringResource = "Plain"
  static let author = "@someone"

  static func makeTab() -> AnyView { AnyView(EmptyView()) }
}

/// A feature without a tab: it shows itself through its settings, Home's corner capsule and the notch, so it makes no
/// tab at all.
@MainActor
private enum TablessModule: FeatureModule {
  static let id: FeatureID = "tabless"
  static let title: LocalizedStringResource = "Tabless"
  static let symbol = "text.viewfinder"
  static let summary: LocalizedStringResource = "Tabless"
  static let details: LocalizedStringResource = "Tabless"
  static let author = "@someone"
  static let hasTab = false
}

@MainActor
struct FeatureDescriptorTests {
  @Test
  func descriptorCarriesTheCatalogFields() {
    let d = SampleModule.descriptor
    #expect(d.isRecommended && d.isBeta && !d.isBuiltIn && d.author == "@someone")
    #expect(d.dataFolder == "Sample" && d.hasOnboardingStep && d.suspension != nil && d.keeps != nil)
  }

  @Test
  func aPlainFeatureIsNeitherRecommendedNorBuiltInNorPaused() {
    let d = PlainModule.descriptor
    #expect(!d.isRecommended && !d.isBeta && !d.isBuiltIn && !d.hasOnboardingStep)
    #expect(d.suspension == nil && d.keeps == nil && d.dataFolder == nil && d.preview == nil)
  }

  /// Every feature has a tab unless it says it has none; the shell reads that from the descriptor, making no view.
  @Test
  func aFeatureHasATabUnlessItSaysItHasNone() {
    #expect(PlainModule.descriptor.hasTab)
    #expect(SampleModule.descriptor.hasTab)
    #expect(!TablessModule.descriptor.hasTab)
    #expect(FeatureDescriptor(id: "plain", title: "Plain", symbol: "circle").hasTab)
  }
}
