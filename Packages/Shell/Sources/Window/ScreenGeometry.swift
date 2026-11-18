import AppKit
import VortexCore

/// Pure geometry of the notch and the window around it.
/// All rects are in global screen coordinates with the origin at the bottom left, as in AppKit.
enum ScreenGeometry {
  /// The notch of a screen, derived from its unobscured top corners; nil when the screen has no notch.
  static func notchRect(
    screenFrame: CGRect,
    topInset: CGFloat,
    leftAreaWidth: CGFloat?,
    rightAreaWidth: CGFloat?
  ) -> CGRect? {
    guard topInset > 0, let leftAreaWidth, let rightAreaWidth else { return nil }
    let width = screenFrame.width - leftAreaWidth - rightAreaWidth
    guard width > 0 else { return nil }
    return CGRect(x: screenFrame.minX + leftAreaWidth, y: screenFrame.maxY - topInset, width: width, height: topInset)
  }

  /// The window hanging from the notch, its top edge at the top of the screen, wide enough for the concave shoulders
  /// on both sides. The regular window is centered on the notch; the large one keeps its left edge and grows right,
  /// moving left only as far as the visible area needs.
  static func notchWindowFrame(
    notch: CGRect,
    screenFrame: CGRect,
    visibleFrame: CGRect,
    size: WindowSize,
    shoulder: CGFloat
  ) -> CGRect {
    let regularX = notch.midX - (WindowSize.regular.size.width + shoulder * 2) / 2
    let content = size.size
    let width = content.width + shoulder * 2
    let x = size == .regular ? regularX : max(min(regularX, visibleFrame.maxX - width), visibleFrame.minX)
    return CGRect(x: x, y: screenFrame.maxY - content.height, width: width, height: content.height)
  }

  /// The window under the menu bar icon on screens without a notch, kept inside the visible area: the regular window
  /// is centered under the icon, the large one keeps its left edge and grows right as far as there is room.
  static func menuBarWindowFrame(
    anchor: CGRect,
    visibleFrame: CGRect,
    size: WindowSize,
    gap: CGFloat = 6,
    margin: CGFloat = 8
  ) -> CGRect {
    let regular = WindowSize.regular.size.width
    let regularX = min(max(anchor.midX - regular / 2, visibleFrame.minX + margin), visibleFrame.maxX - margin - regular)
    let content = size.size
    let x = max(min(regularX, visibleFrame.maxX - margin - content.width), visibleFrame.minX + margin)
    return CGRect(x: x, y: visibleFrame.maxY - gap - content.height, width: content.width, height: content.height)
  }

  /// Where the notch cuts into the window's content (the window without its shoulders), in the content's coordinates
  /// with the origin at the top left.
  static func notchCutout(notch: CGRect, windowFrame: CGRect, shoulder: CGFloat) -> CGRect {
    CGRect(x: notch.minX - windowFrame.minX - shoulder, y: 0, width: notch.width, height: notch.height)
  }

  /// The closed notch with ears of the given width on both sides; just the notch when there are no ears.
  static func earsFrame(notch: CGRect, earWidth: CGFloat, shoulder: CGFloat) -> CGRect {
    guard earWidth > 0 else { return notch }
    return notch.insetBy(dx: -(earWidth + shoulder), dy: 0)
  }
}

extension NSScreen {
  var displayID: CGDirectDisplayID {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
  }

  /// The hardware notch of this screen, nil when there is none.
  var notchRect: CGRect? {
    ScreenGeometry.notchRect(
      screenFrame: frame,
      topInset: safeAreaInsets.top,
      leftAreaWidth: auxiliaryTopLeftArea?.width,
      rightAreaWidth: auxiliaryTopRightArea?.width
    )
  }
}
