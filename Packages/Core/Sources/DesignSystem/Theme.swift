import AppKit
import SwiftUI

/// Monochrome palette from the design canvas. Every color adapts to light and dark appearance.
public enum VortexColor {
  public static let windowBackground = dynamic(dark: 0x050505, light: 0xFBFBFC)
  public static let raised = dynamic(dark: 0x1A1A1D, light: 0xEDEDF0)
  public static let line = dynamic(dark: 0x1B1B1E, light: 0xE6E6EA)
  public static let primaryText = dynamic(dark: 0xF5F5F7, light: 0x1D1D1F)
  public static let secondaryText = dynamic(dark: 0x8E8E93, light: 0x5E5E63)
  public static let tertiaryText = dynamic(dark: 0x7C7C82, light: 0x6B6B70)
  public static let track = dynamic(dark: 0x2A2A2E, light: 0xDEDEE2)
  /// Cards such as clipboard items; in the light theme they sit on the window with a hairline edge, see `cardEdge`.
  public static let card = dynamic(dark: 0x111113, light: 0xFFFFFF)
  public static let cardEdge = dynamic(dark: 0x111113, light: 0xE3E3E8)
  /// Background of thumbnails and file previews.
  public static let thumbnail = dynamic(dark: 0x18181B, light: 0xE6E6EA)
  /// Dashed outline of drop zones.
  public static let dropOutline = dynamic(dark: 0x3A3A3F, light: 0xC4C4CA)
  /// Fill of the one primary action on a screen.
  public static let accent = dynamic(dark: 0xF5F5F7, light: 0x1D1D1F)
  /// Text and icons on top of `accent`.
  public static let onAccent = dynamic(dark: 0x0A0A0A, light: 0xFFFFFF)
  /// The hardware notch and everything drawn inside it: black in both themes.
  public static let notch = Color.black
  public static let notchText = Color(white: 0.96)
  public static let notchTrack = Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x2E / 255)

  private static func dynamic(dark: UInt32, light: UInt32) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(hex: isDark ? dark : light)
      }
    )
  }
}

extension NSColor {
  convenience init(hex: UInt32) {
    self.init(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}

/// Sizes of the window that grows out of the notch.
public enum VortexMetrics {
  public static let windowSize = CGSize(width: 680, height: 440)
  public static let sidebarWidth: CGFloat = 56
  /// Height of the top row that flanks the notch.
  public static let headerHeight: CGFloat = 52
  /// Concave fillet where the window meets the top edge of the screen.
  public static let shoulder: CGFloat = 10
  public static let windowCornerRadius: CGFloat = 30
  /// Bottom corners of the hardware notch.
  public static let notchCornerRadius: CGFloat = 10
  /// Corner radius when the window opens under the menu bar icon.
  public static let menuBarWindowCornerRadius: CGFloat = 18
  /// Minimum size of anything clickable.
  public static let hitTarget: CGFloat = 44
}

extension EnvironmentValues {
  /// Where the hardware notch cuts into the current view, in the view's own coordinates; nil without a notch.
  @Entry public var notchCutout: CGRect? = nil
  /// Whether the window is open. Tabs stay mounted while it is closed; use `.task(id: isWindowOpen)`
  /// for work that should run only while they are visible.
  @Entry public var isWindowOpen = false
}
