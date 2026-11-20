import AppKit
import SwiftUI

/// The monochrome palette. Every color adapts to light and dark appearance.
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
  /// The cards of Home's widgets.
  public static let dock = dynamic(dark: 0x0E0E10, light: 0xF1F1F4)
  /// A side panel next to a window's content, as Home's editor has: a shade off the window.
  public static let panel = dynamic(dark: 0x09090A, light: 0xF6F6F8)
  /// Fill of the one primary action on a screen.
  public static let accent = dynamic(dark: 0xF5F5F7, light: 0x1D1D1F)
  /// Text and icons on top of `accent`.
  public static let onAccent = dynamic(dark: 0x0A0A0A, light: 0xFFFFFF)
  /// The one color outside the monochrome palette: a permission the user skipped (`WarningMark`). The system yellow,
  /// which macOS adjusts for light and dark.
  public static let warning = Color(nsColor: .systemYellow)
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

/// The sizes the window takes. Every tab fits the regular one; a few pages, such as the catalog, need the large one,
/// which grows right from the regular window's left edge, so the sidebar stays where it is. So does Home's utilities
/// dock, by a strip of its own. On a wide notch the regular window is wider (`VortexMetrics.regularWidth(notchWidth:)`),
/// and the other two are built on it.
public enum WindowSize: Sendable, Equatable {
  /// 680×440, wider on a wide notch.
  case regular
  /// The regular window and, at its right, 200 pt more: 880×440.
  case large
  /// The regular window and, at its right, the strip of Home's utilities dock, as wide as the sidebar: 736×440.
  case dock

  /// The size on a display whose notch is `notchWidth` points wide; nil without a notch, as under the menu bar icon.
  public func size(notchWidth: CGFloat?) -> CGSize {
    let regular = VortexMetrics.regularWidth(notchWidth: notchWidth)
    let height = VortexMetrics.windowSize.height
    return switch self {
    case .regular: CGSize(width: regular, height: height)
    case .large: CGSize(width: regular + VortexMetrics.largeExtraWidth, height: height)
    case .dock: CGSize(width: regular + VortexMetrics.dockWidth, height: height)
    }
  }

  /// The size without a notch, and on any notch up to 186 pt, as a 14" or 16" MacBook Pro's 185 pt at its default
  /// scale: 680×440, 880×440, 736×440.
  public var size: CGSize { size(notchWidth: nil) }
}

/// Sizes of the window that grows out of the notch.
public enum VortexMetrics {
  /// The regular window, `WindowSize.regular`, without a notch and on a notch up to 186 pt.
  public static let windowSize = CGSize(width: 680, height: 440)
  /// What the large window adds at the regular one's right, for Home's editor panel and the catalog.
  public static let largeExtraWidth: CGFloat = 200
  public static let sidebarWidth: CGFloat = 56
  /// The strip of Home's utilities dock at the window's right: as wide as the sidebar at its left, with its 44 pt
  /// targets in one column.
  public static let dockWidth: CGFloat = sidebarWidth
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
  /// The room Home's notch row gives its widget right of the notch, from the notch's edge, the widget's gap to it
  /// included: the widest the row shows, the Timer's «+5», «+10» and «Старт» in Ukrainian, takes 12 + 190 pt (12 + 183
  /// in English), and a point is to spare. The utilities button's slot (`hitTarget`) follows at the row's end; left of
  /// the notch the row has more room, as the sidebar is narrower than the two.
  public static let notchRowSide: CGFloat = 203

  /// The regular window's width on a display whose notch is `notchWidth` points wide (nil without one): 680, or, on a
  /// notch too wide for Home's notch row to keep `notchRowSide` and the utilities button's slot right of it, wider by
  /// as much as the row needs, equally on both sides, so the notch stays in the window's middle: 680 up to a 186 pt
  /// notch, 696 on 202, 714 on 220, 734 on 240. Whole points.
  public static func regularWidth(notchWidth: CGFloat?) -> CGFloat {
    guard let notchWidth else { return windowSize.width }
    return max(windowSize.width, (notchWidth + 2 * (notchRowSide + hitTarget)).rounded(.up))
  }
}

extension EnvironmentValues {
  /// Where the hardware notch cuts into the current view, in the view's own coordinates; nil without a notch.
  @Entry public var notchCutout: CGRect? = nil
  /// Whether the window is open. Tabs stay mounted while it is closed; use `.task(id: isWindowOpen)`
  /// for work that should run only while they are visible.
  @Entry public var isWindowOpen = false
}
