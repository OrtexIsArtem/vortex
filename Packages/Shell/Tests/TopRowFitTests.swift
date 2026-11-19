#if canImport(FeatureHome) && canImport(FeatureTimer)
  import AppKit
  import FeatureTimer
  import SwiftUI
  import Testing
  import VortexCore

  @testable import FeatureHome

  /// Home's top row with the shipped Timer in it: the notch stays in the window's middle, and the utilities button fits
  /// right of the timer's controls, so the window keeps its width either side of the notch. Measured in English: the
  /// tests have no translations, and QA's snapshots show the Ukrainian row, 7 pt wider.
  @MainActor
  struct TopRowFitTests {
    /// The notch of a 14" or 16" MacBook Pro at its default scale, as QA mode pretends one.
    static let notch = CGSize(width: 185, height: 32)

    /// Where the notch cuts into Home's tab, the regular window centered on it.
    static var cutout: CGRect {
      let x = (WindowSize.regular.size.width - notch.width) / 2 - VortexMetrics.sidebarWidth
      return CGRect(x: x, y: 0, width: notch.width, height: notch.height)
    }

    /// The timer's widget, laid out at the width its own controls take, ends before the button's slot at the row's
    /// right end. Measured idle, at its widest: «+5», «+10» and Start; a run's pause and stop take less.
    @Test
    func theTimersControlsAndTheUtilitiesButtonFitRightOfTheNotch() throws {
      let widget = try #require(TimerModule.makeHomeWidgets().first { $0.place == .notchRow })
      let host = NSHostingView(rootView: widget.view.environment(\.notchCutout, Self.cutout).fixedSize())
      let room = HomeView.gridWidth - UtilitiesButton.slot
      #expect(host.fittingSize.width <= room, "the row's widget takes \(host.fittingSize.width) pt of \(room)")
    }
  }
#endif
