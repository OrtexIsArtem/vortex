import AppKit

/// The Vortex spiral from the design, drawn in code so it stays crisp at any scale.
enum VortexGlyph {
  /// Quarter arcs of the spiral in a 24×24 box with the y axis pointing down: center, radius, start and end angle.
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
      var isFirstPoint = true
      for arc in arcs {
        for step in 0...12 {
          let angle = (arc.start + (arc.end - arc.start) * CGFloat(step) / 12) * .pi / 180
          let point = CGPoint(
            x: (arc.center.x + arc.radius * cos(angle) + offset) * scale,
            y: (arc.center.y + arc.radius * sin(angle) + offset) * scale
          )
          if isFirstPoint {
            path.move(to: point)
            isFirstPoint = false
          } else {
            path.line(to: point)
          }
        }
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
