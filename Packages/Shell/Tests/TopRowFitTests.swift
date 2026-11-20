#if canImport(FeatureHome) && canImport(FeatureTimer)
  import AppKit
  import FeatureTimer
  import Foundation
  import SwiftUI
  import Testing
  import VortexCore

  @testable import FeatureHome
  @testable import VortexShell

  /// Home's top row with the shipped Timer in it, on notches from a 14" or 16" MacBook Pro's 185 pt at its default scale
  /// to 240 pt: the window grows equally on both sides of the notch as far as the row needs, so the timer's controls and
  /// the utilities button fit right of the notch, in English and in Ukrainian, and the notch stays in the middle.
  @MainActor
  struct TopRowFitTests {
    /// The notch's width, and the regular window's on it: 680 up to a 186 pt notch, then wider by as much.
    static let widths: [(notch: CGFloat, window: CGFloat)] = [(185, 680), (202, 696), (220, 714), (240, 734)]

    /// The Timer's Start in Ukrainian, from its String Catalog. `swift test` builds no catalogs, so the views show
    /// English; the Ukrainian row is measured as the English one with this word in place of "Start".
    static func ukrainianStart() throws -> String {
      let timer = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Features/Timer/Sources/Resources/Localizable.xcstrings")
      let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: timer)) as? [String: Any])
      let strings = try #require(catalog["strings"] as? [String: Any])
      let start = try #require(strings["Start"] as? [String: Any])
      let localizations = try #require(start["localizations"] as? [String: Any])
      let uk = try #require(localizations["uk"] as? [String: Any])
      let unit = try #require(uk["stringUnit"] as? [String: Any])
      return try #require(unit["value"] as? String)
    }

    /// A word's width in the Start button's font.
    static func width(_ word: String) -> CGFloat {
      NSHostingView(rootView: Text(verbatim: word).font(.system(size: 13, weight: .semibold)).fixedSize()).fittingSize.width
    }

    /// The timer's widget, laid out at the width its own controls take, idle, at its widest («+5», «+10» and Start; a
    /// run's pause and stop take less), ends before the utilities button's slot at the row's right end, in English and
    /// in Ukrainian. The row spans the window from the sidebar to the right edge, the notch in the window's middle.
    @Test
    func theTimersControlsAndTheUtilitiesButtonFitRightOfTheNotch() throws {
      let widget = try #require(TimerModule.makeHomeWidgets().first { $0.place == .notchRow })
      let ukrainian = try Self.width(Self.ukrainianStart()) - Self.width("Start")
      #expect(ukrainian > 0, "«Старт» is wider than «Start»")
      for (notch, expected) in Self.widths {
        let window = WindowSize.regular.size(notchWidth: notch).width
        #expect(window == expected, "a \(notch) pt notch")
        // Where the notch cuts into Home's tab, the window centered on it.
        let cutout = CGRect(x: (window - notch) / 2 - VortexMetrics.sidebarWidth, y: 0, width: notch, height: 32)
        let row = window - VortexMetrics.sidebarWidth - UtilitiesButton.slot
        let host = NSHostingView(rootView: widget.view.environment(\.notchCutout, cutout).fixedSize())
        let english = host.fittingSize.width
        #expect(english <= row, "a \(notch) pt notch: the row's widget takes \(english) pt of \(row) in English")
        #expect(english + ukrainian <= row, "a \(notch) pt notch: \(english + ukrainian) pt of \(row) in Ukrainian")
      }
    }

    /// The window opens with the notch in its middle on every one of these notches, wider on both sides alike.
    @Test
    func theNotchStaysInTheWindowsMiddle() {
      let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
      for (notch, window) in Self.widths {
        let rect = CGRect(x: (screen.width - notch) / 2, y: screen.maxY - 32, width: notch, height: 32)
        let frame = ScreenGeometry.notchWindowFrame(
          notch: rect, screenFrame: screen, visibleFrame: screen, size: .regular, shoulder: VortexMetrics.shoulder
        )
        #expect(frame.width == window + 2 * VortexMetrics.shoulder && frame.midX == rect.midX, "a \(notch) pt notch")
      }
    }
  }
#endif
