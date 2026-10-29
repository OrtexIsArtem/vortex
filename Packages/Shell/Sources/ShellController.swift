import AppKit
import ComposableArchitecture
import FeatureRegistry
import VortexCore
import VortexPlatform

/// Starts the shell: loads settings, creates the store and puts the notch, window and menu bar icon on screen.
@MainActor
public final class ShellController: NSObject {
  private let store: StoreOf<ShellFeature>
  #if DEBUG
    private var qaReadiness: ObserveToken?
    private var isQAStarted = false
  #endif

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
      // A QA run takes commands only on its own channel, never the debug notifications every debug build answers.
      if QA.isActive {
        ShellQA.install(store: store)
        startQAWhenReady()
      } else {
        listenForDebugCommands()
      }
    #endif
  }

  #if DEBUG
    /// A QA run says it is ready (and starts listening) only once the shell hears window events and every feature is
    /// started, so the first command never lands before them or before a feature's own commands exist.
    private func startQAWhenReady() {
      WindowController.shared.qaOnEventsSubscribed = { [weak self] in self?.startQAIfReady() }
      qaReadiness = observe { [weak self] in
        guard let self else { return }
        _ = self.store.isStarted
        self.startQAIfReady()
      }
    }

    private func startQAIfReady() {
      guard !isQAStarted, store.isStarted, WindowController.shared.qaHasEventsSubscriber else { return }
      isQAStarted = true
      QA.start()
    }
  #endif

  #if DEBUG
    /// Call first in main.swift, before anything else: a QA run (`--qa <name>`) gets its own folder and simulated
    /// system clients before anything reads one, and a bad `--qa` stops the app here. Nothing happens without `--qa`.
    public static func prepareQA() {
      QA.bootstrap()
    }

    /// Whether the app with this process id is the same kind of instance as this one: the same QA run, or both plain
    /// Vortex. Only those take over from each other.
    public static func isSameQARun(pid: pid_t) -> Bool {
      QA.isSameRun(pid: pid)
    }
  #endif

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

  /// Menu of the menu bar icon, shown on right click. Each item has an identifier, which QA's `entry kind=menu item=…`
  /// names.
  private func makeMenu() -> NSMenu {
    let menu = NSMenu()
    func add(_ title: String, _ action: Selector, key: String, id: String) {
      let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
      item.target = self
      item.identifier = NSUserInterfaceItemIdentifier(id)
    }
    add(String(localized: "Open Vortex", bundle: .module), #selector(openFromMenu), key: "", id: "open")
    add(String(localized: "Settings…", bundle: .module), #selector(openSettingsFromMenu), key: ",", id: "settings")
    menu.addItem(.separator())
    add(String(localized: "Quit Vortex", bundle: .module), #selector(quitFromMenu), key: "q", id: "quit")
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
    /// `io.github.ortexisartem.vortex.debug.permissions` asks now for Screen Recording and Automation of the running
    /// browsers,
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
          // `section`: general, activation or features.
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
        // Screen Recording, then Automation of each running browser; the system asks once for each.
        _ = ScreenCaptureClient.liveValue.requestAccess()
        MainActor.assumeIsolated { FrontWindowClient.askForBrowserAutomation() }
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
