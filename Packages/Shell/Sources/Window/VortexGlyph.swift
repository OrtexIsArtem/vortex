import AppKit

/// The Vortex spiral from the design, drawn in code so it stays crisp at any scale.
enum VortexGlyph {
  /// Quarter arcs of the spiral in a 24×24 box with the y axis pointing down: center, radius, start and end angle.
  /// Each arc starts where the previous one ends.
  private static let arcs: [(center: CGPoint, radius: CGFloat, start: CGFloat, end: CGFloat)] = [
    (CGPoint(x: 13.5, y: 12), 1.5, 180, 270),
    (CGPoint(x: 13.5, y: 13.5), 3, 270, 360),
    (CGPoint(x: 12, y: 13.5), 4.5, 0, 90),
    (CGPoint(x: 12, y: 12), 6, 90, 180),
    (CGPoint(x: 13.5, y: 12), 7.5, 180, 270),
  ]

  /// Template image for the menu bar; macOS tints it for light and dark menu bars.
  static func menuBarImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
      let scale = rect.width / 24
      // The spiral's bounding box is centered at (11.25, 11.25); shift it to the middle of the box.
      let offset: CGFloat = 0.75
      let path = NSBezierPath()
      path.lineWidth = 2.1 * scale
      path.lineCapStyle = .round
      path.lineJoinStyle = .round
      let start = arcs[0]
      path.move(to: CGPoint(
        x: (start.center.x - start.radius + offset) * scale,
        y: (start.center.y + offset) * scale
      ))
      for arc in arcs {
        // In the flipped context growing angles turn clockwise on screen, like the SVG the spiral comes from.
        path.appendArc(
          withCenter: CGPoint(x: (arc.center.x + offset) * scale, y: (arc.center.y + offset) * scale),
          radius: arc.radius * scale,
          startAngle: arc.start,
          endAngle: arc.end,
          clockwise: false
        )
      }
      NSColor.black.setStroke()
      path.stroke()
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Vortex"
    return image
  }
}
