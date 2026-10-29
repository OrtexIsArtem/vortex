#if DEBUG
  import AppKit

  /// What the guard needs of a window; NSWindow has it all, and tests use a stand-in that never reaches a display.
  @MainActor
  protocol QAGuardedWindow: AnyObject {
    var isVisible: Bool { get }
    var frame: NSRect { get }
    var occlusionState: NSWindow.OcclusionState { get }
    func orderOut(_ sender: Any?)
    func setFrameOrigin(_ point: NSPoint)
  }

  extension NSWindow: QAGuardedWindow {}

  /// Watches that a QA run leaves no trace on screen, as a violation each time: any window of the app that shows on a
  /// display is ordered out and moved off the displays, a window that takes the keyboard is ordered out, and Vortex
  /// coming to the front gives the front back. Windows are placed off the displays and can't take the keyboard in the
  /// first place (`QA.offscreen`, `QA.allowsKeyWindows`); this is the second line.
  ///
  /// It is installed when the shell starts, before any window of the run can show, and checks every window up then.
  /// After that it checks a window whenever it shows or hides (occlusion), moves, resizes or changes display, every
  /// window when the displays change, and every window the `state` command lists.
  @MainActor
  enum QAWindowGuard {
    private static var observers: [any NSObjectProtocol] = []

    static func install() {
      defer { checkAll() }
      guard observers.isEmpty else { return }
      let center = NotificationCenter.default
      let windowNotifications: [Notification.Name] = [
        NSWindow.didChangeOcclusionStateNotification,
        NSWindow.didMoveNotification,
        NSWindow.didResizeNotification,
        NSWindow.didChangeScreenNotification,
      ]
      observers = windowNotifications.map { name in
        center.addObserver(forName: name, object: nil, queue: .main) { note in
          let window = note.object as? NSWindow
          MainActor.assumeIsolated { window.map { check($0) } }
        }
      } + [
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
          MainActor.assumeIsolated { checkAll() }
        },
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
          let window = note.object as? NSWindow
          MainActor.assumeIsolated {
            guard let window else { return }
            // The keys of the app the user types in would go into a window nobody sees: it goes at once.
            QALog.violation("window", "took the keyboard, ordered out", describe(window))
            window.orderOut(nil)
          }
        },
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
          MainActor.assumeIsolated {
            QALog.violation("app", "came to the front")
            NSApp.deactivate()
          }
        },
      ]
    }

    /// Whether some part of the window is on a display, where the user could see it.
    static func isOnDisplay(
      _ window: some QAGuardedWindow,
      displays: [CGRect] = NSScreen.screens.map(\.frame)
    ) -> Bool {
      window.isVisible && (
        window.occlusionState.contains(.visible)
          || displays.contains { $0.intersects(window.frame) }
      )
    }

    /// Every window of the app.
    static func checkAll() {
      for window in NSApp?.windows ?? [] {
        check(window)
      }
    }

    /// A window on a display is a violation: it is ordered out and moved off the displays.
    static func check(_ window: some QAGuardedWindow, displays: [CGRect] = NSScreen.screens.map(\.frame)) {
      guard isOnDisplay(window, displays: displays) else { return }
      QALog.violation("window", "showed on a display, ordered out", describe(window))
      window.orderOut(nil)
      window.setFrameOrigin(QA.offscreen(window.frame).origin)
    }

    private static func describe(_ window: some QAGuardedWindow) -> [String: String] {
      let frame = window.frame
      return [
        "class": String(describing: type(of: window)),
        "frame": "\(Int(frame.minX)) \(Int(frame.minY)) \(Int(frame.width))×\(Int(frame.height))",
      ]
    }
  }

  /// Draws a window's content the way the app draws it on screen, with `cacheDisplay`: no screen capture, and the same
  /// whether or not the window is on a display.
  ///
  /// `cacheDisplay` draws layers without their Core Animation filters, which the screen applies. SwiftUI tints some SF
  /// Symbols that way: `timer`, `checklist` and `square.grid.2x2` become a white image under a `multiplyColor` filter,
  /// while simpler ones are shapes filled with their colour. So those layers are left out of `cacheDisplay` and drawn
  /// here in their tint, as the screen shows them (B-B3).
  @MainActor
  enum QASnapshot {
    static func png(of window: NSWindow) throws -> (data: Data, size: CGSize, scale: CGFloat) {
      guard let view = window.contentView else { throw QAError("the window has no content") }
      view.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      let bounds = view.bounds
      guard bounds.width > 0, bounds.height > 0, let image = view.bitmapImageRepForCachingDisplay(in: bounds) else {
        throw QAError("the window has no size")
      }
      let tinted = view.layer.map(tintedLayers) ?? []
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      for layer in tinted { layer.layer.isHidden = true }
      view.cacheDisplay(in: bounds, to: image)
      for layer in tinted { layer.layer.isHidden = false }
      CATransaction.commit()
      if let root = view.layer, !tinted.isEmpty, let context = NSGraphicsContext(bitmapImageRep: image)?.cgContext {
        drawTints(tinted, root: root, into: context)
      }
      guard let data = image.representation(using: .png, properties: [:]) else { throw QAError("the PNG could not be made") }
      return (data, bounds.size, CGFloat(image.pixelsWide) / bounds.width)
    }

    /// A layer the screen tints with a `multiplyColor` filter, and that tint.
    struct Tinted {
      let layer: CALayer
      let color: CGColor
    }

    /// Every visible layer under `root` with a `multiplyColor` filter, outermost first; none inside another.
    static func tintedLayers(in root: CALayer) -> [Tinted] {
      var found: [Tinted] = []
      func walk(_ layer: CALayer) {
        guard !layer.isHidden else { return }
        if let color = multiplyColor(of: layer) {
          found.append(Tinted(layer: layer, color: color))
          return
        }
        for sublayer in layer.sublayers ?? [] {
          walk(sublayer)
        }
      }
      walk(root)
      return found
    }

    /// The colour of a layer's `multiplyColor` filter (Core Animation's own filter, which SwiftUI sets).
    static func multiplyColor(of layer: CALayer) -> CGColor? {
      for filter in layer.filters ?? [] {
        guard let object = filter as? NSObject, object.description == "multiplyColor",
              let value = object.value(forKey: "inputColor"), CFGetTypeID(value as CFTypeRef) == CGColor.typeID
        else { continue }
        return (value as! CGColor)
      }
      return nil
    }

    /// Draws each tinted layer into `context`, whose user space is `root`'s: what it draws, in its tint and with the
    /// opacity it and the layers above it have.
    static func drawTints(_ tinted: [Tinted], root: CALayer, into context: CGContext) {
      for item in tinted {
        let opacity = effectiveOpacity(of: item.layer, below: root)
        guard opacity > 0, let transform = transform(from: item.layer, to: root) else { continue }
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.concatenate(transform)
        item.layer.render(in: context)
        // The layer draws a white template: its tint keeps only the shape (the screen multiplies white by it).
        context.setBlendMode(.sourceIn)
        context.setFillColor(item.color.copy(alpha: item.color.alpha * CGFloat(opacity)) ?? item.color)
        context.fill(item.layer.bounds)
        context.endTransparencyLayer()
        context.restoreGState()
      }
    }

    /// The opacity a layer shows with: its own times every layer's above it, up to `root`; zero if one is hidden.
    static func effectiveOpacity(of layer: CALayer, below root: CALayer) -> Float {
      var opacity: Float = 1
      var current: CALayer? = layer
      while let each = current, each !== root {
        if each.isHidden { return 0 }
        opacity *= each.opacity
        current = each.superlayer
      }
      return opacity
    }

    /// The affine map from `layer`'s coordinates to `root`'s, read off three converted points (flips included).
    static func transform(from layer: CALayer, to root: CALayer) -> CGAffineTransform? {
      let origin = layer.convert(CGPoint.zero, to: root)
      let x = layer.convert(CGPoint(x: 1, y: 0), to: root)
      let y = layer.convert(CGPoint(x: 0, y: 1), to: root)
      let transform = CGAffineTransform(a: x.x - origin.x, b: x.y - origin.y, c: y.x - origin.x, d: y.y - origin.y, tx: origin.x, ty: origin.y)
      return transform.isIdentity || transform.a * transform.d - transform.b * transform.c != 0 ? transform : nil
    }
  }
#endif
