import ComposableArchitecture
import SwiftUI
import Testing

@testable import VortexCore

/// A utility that covers the window while it works, as keyboard cleaning does with its lock screen.
@MainActor
private enum CoveringModule: FeatureModule {
  static let id: FeatureID = "covering"
  static let title: LocalizedStringResource = "Covering"
  static let symbol = "rectangle.fill"
  static let summary: LocalizedStringResource = "Covering"
  static let details: LocalizedStringResource = "Covering"
  static let author = "@someone"
  static let kind = FeatureKind.utility

  static func makeWindowCover() -> AnyView? { AnyView(Color.black) }
}

/// A feature that shows nothing over the window.
@MainActor
private enum PlainModule: FeatureModule {
  static let id: FeatureID = "plain"
  static let title: LocalizedStringResource = "Plain"
  static let symbol = "circle"
  static let summary: LocalizedStringResource = "Plain"
  static let details: LocalizedStringResource = "Plain"
  static let author = "@someone"
}

/// The window cover: a utility's screen over the whole window while it works, which the utility puts up and takes down
/// and the shell draws.
@MainActor
struct WindowCoverTests {
  /// A module has no cover unless it makes one.
  @Test
  func aModuleHasACoverOnlyIfItMakesOne() {
    #expect(PlainModule.makeWindowCover() == nil)
    #expect(CoveringModule.makeWindowCover() != nil)
  }

  /// No cover shows until a utility puts one up; it names the utility, and whether Vortex holds the keyboard meanwhile.
  @Test
  func noCoverShowsUntilAUtilityPutsOneUp() {
    @Shared(.windowCover) var cover
    #expect(cover == nil)
    $cover.withLock { $0 = WindowCover(feature: "covering", holdsKeyboard: true) }
    #expect(cover?.feature == "covering" && cover?.holdsKeyboard == true)
    #expect(WindowCover(feature: "covering").holdsKeyboard == false)
    $cover.withLock { $0 = nil }
  }
}
