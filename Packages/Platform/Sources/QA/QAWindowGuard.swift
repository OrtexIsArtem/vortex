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
