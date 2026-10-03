import AppKit
import ComposableArchitecture
import FeatureRegistry
import SwiftUI
import VortexCore
import VortexPlatform

/// Starts the shell: loads settings, creates the store and puts the notch, window and menu bar icon on screen.
@MainActor
public final class ShellController {
  private let store: StoreOf<ShellFeature>
  private let menuTarget = MenuTarget()

  public init() {
    @Dependency(\.settingsClient) var settingsClient
    let state = ShellFeature.State(
      settings: settingsClient.load(),
      features: FeatureRegistry.all.map { $0.descriptor }
    )
    store = Store(initialState: state) {
      ShellFeature()
    }
  }

  public func start() {
    @Dependency(\.notchIndicators) var indicators
    WindowController.shared.install(
      content: ShellWindowView(store: store),
      menu: makeMenu(),
      indicators: indicators
    )
    store.send(.task)
    #if DEBUG
      listenForDebugCommands()
    #endif
  }

  #if DEBUG
    /// Lets scripts drive a debug build without touching the pointer, through distributed notifications:
    /// `io.github.ortexisartem.vortex.debug.toggle` opens or closes the window as the hotkey would,
    /// `io.github.ortexisartem.vortex.debug.indicator` shows or hides a test indicator in the notch.
    private func listenForDebugCommands() {
      let center = DistributedNotificationCenter.default()
      center.addObserver(
        forName: Notification.Name("io.github.ortexisartem.vortex.debug.toggle"),
        object: nil,
        queue: .main
      ) { [store] _ in
        MainActor.assumeIsolated { _ = store.send(.hotkey(.openVortex)) }
      }
      center.addObserver(
        forName: Notification.Name("io.github.ortexisartem.vortex.debug.indicator"),
        object: nil,
        queue: .main
      ) { _ in
        MainActor.assumeIsolated { Self.toggleTestIndicator() }
      }
    }

    static func toggleTestIndicator() {
      @Dependency(\.notchIndicators) var indicators
      let isShown = indicators.indicators["debug"] != nil
      indicators.set(
        isShown ? nil : NotchIndicator(leading: [.progress(0.7)], trailing: [.text("8:42")]),
        for: "debug"
      )
    }
  #endif

  /// Menu of the menu bar icon, shown on right click.
  private func makeMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(item(String(localized: "Open Vortex", bundle: .module)) { [store] in
      store.send(.menuOpenTapped)
    })
    menu.addItem(item(String(localized: "Settings…", bundle: .module), key: ",") { [store] in
      store.send(.menuSettingsTapped)
    })
    menu.addItem(.separator())
    #if DEBUG
      menu.addItem(item("Debug: toggle test indicator") {
        Self.toggleTestIndicator()
      })
      menu.addItem(.separator())
    #endif
    menu.addItem(item(String(localized: "Quit Vortex", bundle: .module), key: "q") { [store] in
      store.send(.quitButtonTapped)
    })
    return menu
  }

  private func item(_ title: String, key: String = "", action: @escaping @MainActor () -> Void) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(MenuTarget.perform(_:)), keyEquivalent: key)
    item.target = menuTarget
    item.representedObject = MenuAction(action)
    return item
  }
}

private final class MenuAction: NSObject {
  let run: @MainActor () -> Void

  init(_ run: @escaping @MainActor () -> Void) {
    self.run = run
  }
}

@MainActor
private final class MenuTarget: NSObject {
  @objc func perform(_ sender: NSMenuItem) {
    (sender.representedObject as? MenuAction)?.run()
  }
}
