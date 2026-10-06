import AppKit
import CoreServices
import ComposableArchitecture
import FeatureRegistry
import VortexCore
import VortexPlatform

/// Starts the shell: loads settings, creates the store and puts the notch, window and menu bar icon on screen.
@MainActor
public final class ShellController: NSObject {
  private let store: StoreOf<ShellFeature>

  override public init() {
    @Dependency(\.settingsClient) var settingsClient
    @Dependency(\.systemClient) var system
    let state = ShellFeature.State(
      settings: settingsClient.load(),
      features: FeatureRegistry.all.map { $0.descriptor },
      language: system.language()
    )
    store = Store(initialState: state) {
      ShellFeature()
    }
    super.init()
  }

  public func start() {
    WindowController.shared.install(content: ShellWindowView(store: store), menu: makeMenu())
    store.send(.task)
    #if DEBUG
      listenForDebugCommands()
    #endif
  }

  /// Files opened with Vortex (`vortex shelf add`, `open -a Vortex`): they go to the feature that takes files.
  /// Works before `start()`, for files that launch the app.
  public func receiveFiles(_ urls: [URL]) {
    store.send(.filesReceived(urls))
  }

  /// Writes the settings at once; called when the app is about to quit, so a pending change is not lost.
  public func saveSettings() {
    @Dependency(\.settingsClient) var settingsClient
    try? settingsClient.save(store.settings)
  }

  /// Menu of the menu bar icon, shown on right click.
  private func makeMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(withTitle: String(localized: "Open Vortex", bundle: .module), action: #selector(openFromMenu), keyEquivalent: "")
      .target = self
    menu.addItem(withTitle: String(localized: "Settings…", bundle: .module), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
      .target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: String(localized: "Quit Vortex", bundle: .module), action: #selector(quitFromMenu), keyEquivalent: "q")
      .target = self
    return menu
  }

  @objc private func openFromMenu() {
    store.send(.menuOpenTapped)
  }

  @objc private func openSettingsFromMenu() {
    store.send(.menuSettingsTapped)
  }

  @objc private func quitFromMenu() {
    store.send(.quitButtonTapped)
  }

  #if DEBUG
    /// Lets scripts drive a debug build without touching the pointer, through distributed notifications:
    /// `io.github.ortexisartem.vortex.debug.toggle` opens or closes the window as the shortcut does,
    /// `io.github.ortexisartem.vortex.debug.indicator` shows or hides a test indicator in the notch,
    /// `io.github.ortexisartem.vortex.debug.permissions` asks now for every permission the features use later,
    /// `io.github.ortexisartem.vortex.debug.tab` switches to a tab (userInfo `id`: a feature id, or `settings` with an
    /// optional `section`).
    private func listenForDebugCommands() {
      let center = DistributedNotificationCenter.default()
      center.addObserver(
        forName: Notification.Name("io.github.ortexisartem.vortex.debug.tab"),
        object: nil,
        queue: .main
      ) { [store] note in
        let info = note.userInfo as? [String: String] ?? [:]
        let id = info["id"] ?? ""
        MainActor.assumeIsolated {
          _ = store.send(.tabSelected(id == "settings" ? .settings : .feature(id)))
          // `section`: general, invocation or features.
          if let section = ShellFeature.SettingsSection.allCases.first(where: { "\($0)" == info["section"] }) {
            _ = store.send(.binding(.set(\.settingsSection, section)))
          }
        }
      }
      center.addObserver(
        forName: Notification.Name("io.github.ortexisartem.vortex.debug.permissions"),
        object: nil,
        queue: .main
      ) { _ in
        // Screen recording, for task screenshots and window titles; the system asks once.
        _ = CGRequestScreenCaptureAccess()
        // Automation of each running browser, for the address of the open page; asked once per browser.
        for bundleID in ["com.google.Chrome", "com.apple.Safari"] {
          Thread.detachNewThread {
            var target = AEAddressDesc()
            let created = bundleID.withCString { AECreateDesc(typeApplicationBundleID, $0, strlen($0), &target) }
            guard created == noErr else { return }
            _ = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, true)
            AEDisposeDesc(&target)
          }
        }
      }
      center.addObserver(
        forName: Notification.Name("io.github.ortexisartem.vortex.debug.toggle"),
        object: nil,
        queue: .main
      ) { [store] _ in
        MainActor.assumeIsolated { _ = store.send(.openHotkeyPressed) }
      }
      center.addObserver(
        forName: Notification.Name("io.github.ortexisartem.vortex.debug.indicator"),
        object: nil,
        queue: .main
      ) { _ in
        @Shared(.notchIndicators) var indicators
        $indicators.withLock { indicators in
          indicators["debug"] = indicators["debug"] == nil
            ? NotchIndicator(leading: [.progress(0.7)], trailing: [.text("8:42")])
            : nil
        }
      }
    }
  #endif
}
