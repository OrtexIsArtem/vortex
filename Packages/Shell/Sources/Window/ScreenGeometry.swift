import AppKit

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

  /// The window hanging from the notch: centered on it, its top edge at the top of the screen,
  /// wide enough for the concave shoulders on both sides.
  static func notchWindowFrame(notch: CGRect, screenFrame: CGRect, size: CGSize, shoulder: CGFloat) -> CGRect {
    let width = size.width + shoulder * 2
    return CGRect(x: notch.midX - width / 2, y: screenFrame.maxY - size.height, width: width, height: size.height)
  }

  /// The window under the menu bar icon on screens without a notch, kept inside the visible area.
  static func menuBarWindowFrame(
    anchor: CGRect,
    visibleFrame: CGRect,
    size: CGSize,
    gap: CGFloat = 6,
    margin: CGFloat = 8
  ) -> CGRect {
    let preferredX = anchor.midX - size.width / 2
    let x = min(max(preferredX, visibleFrame.minX + margin), visibleFrame.maxX - margin - size.width)
    return CGRect(x: x, y: visibleFrame.maxY - gap - size.height, width: size.width, height: size.height)
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
