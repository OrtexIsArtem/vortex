import ComposableArchitecture
import Foundation
import UserNotifications

/// Notifications Vortex shows in Notification Center, with buttons.
@DependencyClient
public struct NotificationClient: Sendable {
  /// A button on a notification; `id` comes back from `buttonPresses` when the user presses it.
  public struct Button: Equatable, Sendable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
      self.id = id
      self.title = title
    }
  }

  /// Asks the user, the first time only, whether Vortex may show notifications; returns the answer.
  public var requestAuthorization: @Sendable () async -> Bool = { false }
  /// Shows a notification now, without a sound. A notification with the same `id` is replaced. Cancelled before it is
  /// shown, it isn't.
  public var post: @Sendable (_ id: String, _ title: String, _ body: String, _ buttons: [Button]) async -> Void
  /// Takes the notification with `id` out of Notification Center, if it is still there.
  public var remove: @Sendable (_ id: String) async -> Void
  /// The ids of the buttons the user presses on Vortex notifications from now on.
  public var buttonPresses: @Sendable () async -> AsyncStream<String> = { .finished }
}

extension NotificationClient: DependencyKey {
  public static let liveValue = NotificationClient(
    requestAuthorization: { await Notifications.shared.requestAuthorization() },
    post: { id, title, body, buttons in
      await Notifications.shared.post(id: id, title: title, body: body, buttons: buttons)
    },
    remove: { id in await Notifications.shared.remove(id: id) },
    buttonPresses: { await Notifications.shared.buttonPresses() }
  )

  public static let testValue = NotificationClient()
}

extension DependencyValues {
  public var notificationClient: NotificationClient {
    get { self[NotificationClient.self] }
    set { self[NotificationClient.self] = newValue }
  }
}

/// The delegate of the notification center: banners show even while Vortex is the active app, and button presses
/// reach `buttonPresses`. UNUserNotificationCenter needs an app bundle, so nothing here runs in `swift test`.
@MainActor
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
  static let shared = Notifications()
  private var listeners: [UUID: AsyncStream<String>.Continuation] = [:]
  /// One category per set of buttons, registered on first use.
  private var categories: [String: UNNotificationCategory] = [:]

  private var center: UNUserNotificationCenter {
    let center = UNUserNotificationCenter.current()
    if center.delegate !== self { center.delegate = self }
    return center
  }

  func remove(id: String) {
    center.removeDeliveredNotifications(withIdentifiers: [id])
    center.removePendingNotificationRequests(withIdentifiers: [id])
  }

  func requestAuthorization() async -> Bool {
    (try? await center.requestAuthorization(options: [.alert])) ?? false
  }

  func post(id: String, title: String, body: String, buttons: [NotificationClient.Button]) async {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    if !buttons.isEmpty {
      let category = "buttons:" + buttons.map(\.id).joined(separator: ",")
      if categories[category] == nil {
        categories[category] = UNNotificationCategory(
          identifier: category,
          actions: buttons.map { UNNotificationAction(identifier: $0.id, title: $0.title, options: []) },
          intentIdentifiers: []
        )
        center.setNotificationCategories(Set(categories.values))
        // Registering categories is asynchronous: reading them back waits for it, so the first post has its buttons.
        _ = await center.notificationCategories()
      }
      content.categoryIdentifier = category
    }
    // Waiting for the categories or the permission, it may have been given up for a newer notification.
    guard !Task.isCancelled else { return }
    try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
  }

  func buttonPresses() -> AsyncStream<String> {
    _ = center
    let (stream, continuation) = AsyncStream.makeStream(of: String.self)
    let id = UUID()
    listeners[id] = continuation
    continuation.onTermination = { _ in
      Task { @MainActor in Notifications.shared.listeners[id] = nil }
    }
    return stream
  }

  private func pressed(_ button: String) {
    for listener in listeners.values {
      listener.yield(button)
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let button = response.actionIdentifier
    guard button != UNNotificationDefaultActionIdentifier, button != UNNotificationDismissActionIdentifier else { return }
    await pressed(button)
  }
}
