import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// Entry point the app shell reads; registered in Features/Registry.
@MainActor
public enum TasksModule: FeatureModule {
  public static let id: FeatureID = TasksFeature.id
  public static let title = LocalizedStringResource("Tasks", bundle: .atURL(Bundle.module.bundleURL))
  public static let symbol = "checklist"
  public static let permissionNeeds = [
    PermissionNeed(
      .screenRecording,
      reason: LocalizedStringResource("Turns a screenshot into a new task.", bundle: .atURL(Bundle.module.bundleURL))
    ),
  ]

  /// One store for the life of the app: the shortcut works while the window is closed.
  static let store = Store(initialState: TasksFeature.State()) {
    TasksFeature()
  }

  private static var overlay: CaptureOverlay?
  private static var screenOverlay: TaskScreenOverlay?

  public static func makeTab() -> AnyView {
    AnyView(TasksView(store: store))
  }

  public static func makeSettings() -> AnyView? {
    AnyView(TasksSettingsView(store: store))
  }

  public static func setEnabled(_ isEnabled: Bool) {
    if overlay == nil {
      overlay = CaptureOverlay(store: store)
      screenOverlay = TaskScreenOverlay(store: store)
      #if DEBUG
        listenForDebugCommands()
      #endif
    }
    store.send(isEnabled ? .start : .stop)
  }

  #if DEBUG
    /// Lets scripts drive a capture in a debug build, through distributed notifications:
    /// `io.github.ortexisartem.vortex.debug.taskCapture` presses the shortcut,
    /// `…taskFrame` draws a frame (userInfo `x`, `y`, `width`, `height` in points from the screen's top left),
    /// `…taskSave` saves (userInfo `title`, optional), `…taskCancel` presses Esc.
    private static func listenForDebugCommands() {
      let center = DistributedNotificationCenter.default()
      func on(_ name: String, _ handle: @escaping @MainActor ([String: String]) -> Void) {
        center.addObserver(forName: Notification.Name("io.github.ortexisartem.vortex.debug.\(name)"), object: nil, queue: .main) { note in
          let info = note.userInfo as? [String: String] ?? [:]
          MainActor.assumeIsolated { handle(info) }
        }
      }
      on("taskCapture") { _ in store.send(.captureRequested) }
      // `…taskCaptureImage` freezes on the image file at userInfo `path` instead of the screen, as if it had been
      // taken on the main display; the source is read as for a real capture.
      on("taskCaptureImage") { info in
        guard let path = info["path"], let screenshot = Screenshot.mainDisplay(showing: URL(fileURLWithPath: path)) else {
          return
        }
        Task {
          let source = await FrontWindowClient.liveValue.current()
          store.send(.captureTaken(screenshot, source))
        }
      }
      on("taskFrame") { info in
        func value(_ key: String) -> CGFloat { CGFloat(Double(info[key] ?? "") ?? 0) }
        store.send(.capture(.frameEnded(CGRect(x: value("x"), y: value("y"), width: value("width"), height: value("height")))))
      }
      on("taskSave") { info in
        if let title = info["title"] { store.send(.capture(.titleChanged(title))) }
        store.send(.capture(.saveTapped))
      }
      on("taskCancel") { _ in store.send(.capture(.cancelTapped)) }
      // `…taskOpen`, `…taskDone`, `…taskScreen` (shows the whole screen, or closes it), `…taskDelete` (userInfo
      // `number`), `…taskBack`, `…taskQuery` (`text`), `…taskFilter` (`status` active|done, `period`
      // today|yesterday|week|all, `priority` all|low|medium|high).
      func task(_ info: [String: String]) -> TaskItem.ID? {
        store.tasks.first { "\($0.number)" == info["number"] }?.id
      }
      on("taskOpen") { info in if let id = task(info) { store.send(.taskTapped(id)) } }
      on("taskDone") { info in if let id = task(info) { store.send(.doneTapped(id)) } }
      on("taskBack") { _ in store.send(.backTapped) }
      on("taskScreen") { info in if let id = task(info) { store.send(.screenTapped(id)) } }
      on("taskSource") { info in if let id = task(info) { store.send(.openSourceTapped(id)) } }
      on("taskDelete") { info in if let id = task(info) { store.send(.deleteTapped(id)) } }
      // `…taskClearDone` presses «Очистити список» in «Виконані», `…taskUndo` the toast's «Скасувати».
      on("taskClearDone") { _ in store.send(.clearDoneTapped) }
      on("taskUndo") { _ in store.send(.undoTapped) }
      // `…taskState` writes what the feature holds to the file at userInfo `path`, as JSON.
      on("taskState") { info in
        guard let path = info["path"] else { return }
        let state: [String: Any] = [
          "isEnabled": store.isEnabled,
          "isLoaded": store.isLoaded,
          "screenAccess": ScreenCaptureClient.liveValue.hasAccess(),
          "isCapturing": store.capture != nil,
          "isFramed": store.capture?.isFramed ?? false,
          "suggestion": store.capture?.suggestion ?? "",
          "openTask": store.openTask?.number ?? 0,
          "shownScreen": store.screen.flatMap { store.tasks[id: $0.taskID]?.number } ?? 0,
          "undoable": store.undoable.map { undoable -> String in
            switch undoable {
            case let .done(id): "done \(store.tasks[id: id]?.number ?? 0)"
            case let .deleted(tasks): "deleted " + tasks.map { "\($0.number)" }.joined(separator: ",")
            }
          } ?? "",
          "keyWindow": NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "",
          "frontApp": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "",
          "tasks": store.tasks.map { ["number": $0.number, "title": $0.title, "done": $0.isDone, "text": $0.text ?? "<none>"] },
        ]
        try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
          .write(to: URL(fileURLWithPath: path))
      }
      on("taskQuery") { info in store.send(.queryChanged(info["text"] ?? "")) }
      on("taskFilter") { info in
        var filter = store.filter
        if let status = info["status"] { filter.status = status == "done" ? .done : .active }
        if let period = info["period"] {
          filter.period = ["today": .today, "yesterday": .yesterday, "week": .week][period] ?? .all
        }
        if let priority = info["priority"] {
          filter.priority = ["low": .low, "medium": .medium, "high": .high][priority]
        }
        store.send(.filterChanged(filter))
      }
    }
  #endif
}
