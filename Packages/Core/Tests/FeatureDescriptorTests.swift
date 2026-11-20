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

/// A utility: one clear action, offered by Home's utilities button, its settings and the notch, so it makes no tab at
/// all. Its type says so; it declares no kind.
@MainActor
private enum SampleUtility: UtilityModule {
  static let id: FeatureID = "utility"
  static let title: LocalizedStringResource = "Utility"
  static let symbol = "text.viewfinder"
  static let summary: LocalizedStringResource = "Utility"
  static let details: LocalizedStringResource = "Utility"
  static let author = "@someone"
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

  /// The type is the kind: a `FeatureModule` is a feature, which must make its tab, and a `UtilityModule` a utility,
  /// which makes none. Its kind alone says whether it has a tab, and the shell reads both from the descriptor.
  @Test
  func theTypeIsTheKind() {
    #expect(PlainModule.kind == .feature && PlainModule.descriptor.kind == .feature)
    #expect(PlainModule.descriptor.hasTab && SampleModule.descriptor.hasTab)
    #expect(SampleUtility.kind == .utility && SampleUtility.descriptor.kind == .utility)
    #expect(!SampleUtility.descriptor.hasTab)
    // Through the protocol, as the shell and the registry see a module.
    let modules: [any FeatureModule.Type] = [PlainModule.self, SampleUtility.self]
    #expect(modules.map { $0.kind } == [.feature, .utility])
    #expect(FeatureDescriptor(id: "plain", title: "Plain", symbol: "circle").kind == .feature)
    #expect(!FeatureDescriptor(id: "tool", title: "Tool", symbol: "wrench", kind: .utility).hasTab)
    #expect(FeatureKind.feature.hasTab && !FeatureKind.utility.hasTab)
  }
}
