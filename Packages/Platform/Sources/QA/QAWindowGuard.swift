#if DEBUG
  import AppKit

  /// Watches that a QA run leaves no trace on screen: a window that shows on a display goes off the displays again, and
  /// a window taking the keyboard or Vortex coming to the front are recorded as violations.
  @MainActor
  enum QAWindowGuard {
    private static var observers: [any NSObjectProtocol] = []

    static func install() {
      guard observers.isEmpty else { return }
      let center = NotificationCenter.default
      observers = [
        center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { note in
          let window = note.object as? NSWindow
          MainActor.assumeIsolated { window.map(windowChanged) }
        },
        center.addObserver(forName: NSWindow.didMoveNotification, object: nil, queue: .main) { note in
          let window = note.object as? NSWindow
          MainActor.assumeIsolated { window.map(windowChanged) }
        },
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
          let window = note.object as? NSWindow
          MainActor.assumeIsolated {
            guard let window else { return }
            QALog.violation("window", "took the keyboard", describe(window))
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
    static func isOnDisplay(_ window: NSWindow) -> Bool {
      window.isVisible && (
        window.occlusionState.contains(.visible)
          || NSScreen.screens.contains { $0.frame.intersects(window.frame) }
      )
    }

    private static func windowChanged(_ window: NSWindow) {
      guard isOnDisplay(window) else { return }
      QALog.violation("window", "showed on a display", describe(window))
      window.setFrameOrigin(QA.offscreen(window.frame).origin)
    }

    private static func describe(_ window: NSWindow) -> [String: String] {
      let frame = window.frame
      return [
        "class": String(describing: type(of: window)),
        "frame": "\(Int(frame.minX)) \(Int(frame.minY)) \(Int(frame.width))×\(Int(frame.height))",
      ]
    }
  }

  /// Draws a window's content the way the app draws it on screen, with `cacheDisplay`: no screen capture, and the same
  /// whether or not the window is on a display.
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
      view.cacheDisplay(in: bounds, to: image)
      guard let data = image.representation(using: .png, properties: [:]) else { throw QAError("the PNG could not be made") }
      return (data, bounds.size, CGFloat(image.pixelsWide) / bounds.width)
    }
  }
#endif
