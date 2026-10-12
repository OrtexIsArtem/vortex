import ComposableArchitecture
import Foundation
import UserNotifications

/// Notifications Vortex shows in Notification Center, with buttons.
@DependencyClient
public struct NotificationClient: Sendable {
  /// A press on a button of a notification: which notification, by the id it was posted with, and which button.
  public struct Press: Equatable, Sendable {
    public var notification: String
    public var button: String

    public init(notification: String, button: String) {
      self.notification = notification
      self.button = button
    }
  }

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
  /// Takes the notifications whose id starts with `prefix` out of Notification Center, shown or still on their way.
  public var remove: @Sendable (_ prefix: String) async -> Void
  /// The buttons the user presses on Vortex notifications from now on, with the notification each belongs to.
  public var buttonPresses: @Sendable () async -> AsyncStream<Press> = { .finished }
}

extension NotificationClient: DependencyKey {
  public static let liveValue = NotificationClient(
    requestAuthorization: { await Notifications.shared.requestAuthorization() },
    post: { id, title, body, buttons in
      await Notifications.shared.post(id: id, title: title, body: body, buttons: buttons)
    },
    remove: { prefix in await Notifications.shared.remove(prefix: prefix) },
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
  private var listeners: [UUID: AsyncStream<NotificationClient.Press>.Continuation] = [:]
  /// One category per set of buttons, registered on first use.
  private var categories: [String: UNNotificationCategory] = [:]
  /// Registering is asynchronous: every post with a category's buttons waits for it, also one that starts meanwhile.
  private var registrations: [String: Task<Void, Never>] = [:]

  private var center: UNUserNotificationCenter {
    let center = UNUserNotificationCenter.current()
    if center.delegate !== self { center.delegate = self }
    return center
  }

  func remove(prefix: String) async {
    let center = center
    let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }
    let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
    center.removeDeliveredNotifications(withIdentifiers: delivered)
    center.removePendingNotificationRequests(withIdentifiers: pending)
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
      if registrations[category] == nil {
        categories[category] = UNNotificationCategory(
          identifier: category,
          actions: buttons.map { UNNotificationAction(identifier: $0.id, title: $0.title, options: []) },
          intentIdentifiers: []
        )
        let center = center
        center.setNotificationCategories(Set(categories.values))
        // Reading them back waits until they are registered, so the notification has its buttons.
        registrations[category] = Task { _ = await center.notificationCategories() }
      }
      await registrations[category]?.value
      content.categoryIdentifier = category
    }
    // Waiting for the categories or the permission, it may have been given up for a newer notification.
    guard !Task.isCancelled else { return }
    try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
  }

  func buttonPresses() -> AsyncStream<NotificationClient.Press> {
    _ = center
    let (stream, continuation) = AsyncStream.makeStream(of: NotificationClient.Press.self)
    let id = UUID()
    listeners[id] = continuation
    continuation.onTermination = { _ in
      Task { @MainActor in Notifications.shared.listeners[id] = nil }
    }
    return stream
  }

  private func pressed(_ press: NotificationClient.Press) {
    for listener in listeners.values {
      listener.yield(press)
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
    await pressed(NotificationClient.Press(notification: response.notification.request.identifier, button: button))
  }
}
