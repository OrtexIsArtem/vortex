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
  /// first place (`QA.offscreen`, `QA.allowsKeyWindows`); this is the second line. A visible run (`QA.isVisible`) shows
  /// its notch window and ears on purpose, so there only the keyboard and the front are guarded.
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

    /// A window on a display is a violation: it is ordered out and moved off the displays. Not in a visible run.
    static func check(
      _ window: some QAGuardedWindow,
      displays: [CGRect] = NSScreen.screens.map(\.frame),
      isVisibleRun: Bool = QA.isVisible
    ) {
      guard !isVisibleRun, isOnDisplay(window, displays: displays) else { return }
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
  /// while simpler ones are shapes filled with their colour. So each such layer is tinted in place for the
  /// snapshot: a stand-in holding its drawing multiplied by the tint takes its place in the tree, and the normal render
  /// then applies every clip, mask, layer above it and opacity, as the screen does.
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
      let scale = CGFloat(image.pixelsWide) / bounds.width
      if let root = view.layer {
        withTintsInPlace(in: root, scale: scale) { view.cacheDisplay(in: bounds, to: image) }
      } else {
        view.cacheDisplay(in: bounds, to: image)
      }
      guard let data = image.representation(using: .png, properties: [:]) else { throw QAError("the PNG could not be made") }
      return (data, bounds.size, scale)
    }

    /// A tinted layer, hidden while its stand-in shows in its place.
    struct StandIn {
      let original: CALayer
      let standIn: CALayer
    }

    /// Runs `draw` while every visible layer under `root` that Core Animation tints with `multiplyColor` is replaced by
    /// a stand-in, then puts the tree back as it was. All in one transaction, without animations.
    @discardableResult
    static func withTintsInPlace<T>(in root: CALayer, scale: CGFloat, _ draw: () throws -> T) rethrows -> T {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      let standIns = replaceTintedLayers(in: root, scale: scale)
      defer {
        for item in standIns.reversed() {
          item.standIn.removeFromSuperlayer()
          item.original.isHidden = false
        }
        CATransaction.commit()
      }
      return try draw()
    }

    /// Puts a stand-in above each visible layer with a `multiplyColor` filter, in the same superlayer: its drawing
    /// multiplied by the tint, with the same geometry and opacity, while the original is hidden. Innermost first, so a
    /// tint inside another one is multiplied by both.
    static func replaceTintedLayers(in root: CALayer, scale: CGFloat) -> [StandIn] {
      var replaced: [StandIn] = []
      func walk(_ layer: CALayer) {
        guard !layer.isHidden else { return }
        for sublayer in layer.sublayers ?? [] {
          walk(sublayer)
        }
        guard layer !== root, let color = multiplyColor(of: layer), let superlayer = layer.superlayer,
              let image = tintedImage(of: layer, color: color, scale: scale)
        else { return }
        let standIn = CALayer()
        standIn.bounds = layer.bounds
        standIn.anchorPoint = layer.anchorPoint
        standIn.anchorPointZ = layer.anchorPointZ
        standIn.position = layer.position
        standIn.zPosition = layer.zPosition
        standIn.transform = layer.transform
        standIn.opacity = layer.opacity
        standIn.contents = image
        standIn.contentsGravity = .resize
        standIn.contentsScale = scale
        superlayer.insertSublayer(standIn, above: layer)
        layer.isHidden = true
        replaced.append(StandIn(original: layer, standIn: standIn))
      }
      walk(root)
      return replaced
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

    /// What `layer` and its sublayers draw, at full opacity (its stand-in carries the opacity), multiplied by `color`
    /// component by component, alpha included, as the filter does.
    static func tintedImage(of layer: CALayer, color: CGColor, scale: CGFloat) -> CGImage? {
      let bounds = layer.bounds
      let width = Int((bounds.width * scale).rounded(.up)), height = Int((bounds.height * scale).rounded(.up))
      guard width > 0, height > 0, width * height <= 64_000_000,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let tint = color.converted(to: space, intent: .defaultIntent, options: nil)?.components, tint.count == 4,
            let context = CGContext(
              data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
      else { return nil }
      context.scaleBy(x: scale, y: scale)
      if layer.contentsAreFlipped() {
        // Under a flipped ancestor the stand-in's image is shown flipped too, as the layer's own drawing is: drawn
        // upside down here, it shows the right way up.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
      }
      context.translateBy(x: -bounds.minX, y: -bounds.minY)
      let opacity = layer.opacity
      layer.opacity = 1
      layer.render(in: context)
      layer.opacity = opacity
      guard let data = context.data else { return nil }
      let factors = tint.map { Double(min(max($0, 0), 1)) }
      let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
      for index in 0..<(width * height * 4) {
        pixels[index] = UInt8((Double(pixels[index]) * factors[index % 4]).rounded())
      }
      return context.makeImage()
    }
  }
#endif
