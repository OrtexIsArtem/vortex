import ComposableArchitecture
import Foundation

/// A macOS permission that some part of Vortex needs (S29). Features declare theirs in `FeatureModule.permissionNeeds`;
/// the shell reads every status from macOS and keeps them in `@Shared(.permissionStatuses)`.
public enum Permission: String, CaseIterable, Codable, Sendable {
  case notifications, accessibility, screenRecording, pasteboard

  /// Its name, as System Settings shows it (S32).
  public var title: LocalizedStringResource {
    switch self {
    case .notifications: LocalizedStringResource("Notifications", bundle: .atURL(Bundle.module.bundleURL))
    case .accessibility: LocalizedStringResource("Accessibility", bundle: .atURL(Bundle.module.bundleURL))
    case .screenRecording: LocalizedStringResource("Screen Recording", bundle: .atURL(Bundle.module.bundleURL))
    case .pasteboard: LocalizedStringResource("Paste from Other Apps", bundle: .atURL(Bundle.module.bundleURL))
    }
  }

  /// Vortex can use a grant only after it relaunches: macOS keeps what it allowed this process when it started.
  public var needsRelaunch: Bool {
    self == .screenRecording || self == .pasteboard
  }

  /// macOS grants it in its own prompt, without System Settings: only notifications.
  public var isGrantedInPlace: Bool {
    self == .notifications
  }

  /// What its warning says, as a tooltip and to VoiceOver (S32, S39): "Notifications are off".
  public var offLabel: LocalizedStringResource {
    switch self {
    case .notifications: LocalizedStringResource("Notifications are off", bundle: .atURL(Bundle.module.bundleURL))
    case .accessibility: LocalizedStringResource("Accessibility is off", bundle: .atURL(Bundle.module.bundleURL))
    case .screenRecording: LocalizedStringResource("Screen Recording is off", bundle: .atURL(Bundle.module.bundleURL))
    case .pasteboard: LocalizedStringResource("Paste from Other Apps is off", bundle: .atURL(Bundle.module.bundleURL))
    }
  }
}

/// A dictionary keyed by permission encodes as an object, `{"accessibility": "granted"}`, not as a list of pairs.
extension Permission: CodingKeyRepresentable {}

/// What macOS says about a permission (S1).
public enum PermissionStatus: String, Codable, Sendable {
  /// Not asked, denied, or unknown.
  case notGranted
  /// Works now.
  case granted
  /// macOS granted it, but this process can use it only after a relaunch.
  case grantedAfterRestart
  /// macOS doesn't ask for it on this system, as for the pasteboard on macOS 26.4. Hidden everywhere.
  case notNeeded

  /// The checkbox shows on (S2).
  public var isOn: Bool { self == .granted || self == .grantedAfterRestart }
}

/// A permission a feature needs, with the reason the user reads next to it (S33).
public struct PermissionNeed: Equatable, Sendable {
  public var permission: Permission
  /// One short line from the feature's own bundle: `LocalizedStringResource("…", bundle: .atURL(Bundle.module.bundleURL))`.
  public var reason: LocalizedStringResource

  public init(_ permission: Permission, reason: LocalizedStringResource) {
    self.permission = permission
    self.reason = reason
  }
}

extension SharedReaderKey where Self == InMemoryKey<[Permission: PermissionStatus]>.Default {
  /// Written only by the shell; empty until the first read, and a missing key means "unknown": no badge.
  public static var permissionStatuses: Self {
    Self[.inMemory("permissionStatuses"), default: [:]]
  }
}

extension SharedReaderKey where Self == InMemoryKey<Bool>.Default {
  /// Vortex is blocked (S9, S43): a permission that is required, and needed by an enabled feature or the shell, reads
  /// `notGranted`. Written only by the shell; false until the first read. While it is true, a feature's own shortcut
  /// opens the shell's page with `permissionPage` instead of doing its work.
  public static var appBlocked: Self {
    Self[.inMemory("appBlocked"), default: false]
  }
}

/// Opens the shell's page for one permission (S24). Features call it instead of asking macOS.
///
/// The live `open` leaves the request in a channel inside the app, and the shell takes the requests out with
/// `requests()` from launch on: feature stores are not children of the shell's store, and Core can't import the shell.
/// A request made while nothing listens waits for the shell to start listening; only the latest one waits.
@DependencyClient
public struct PermissionPage: Sendable {
  public var open: @Sendable (_ permission: Permission) async -> Void
  /// The pages features ask for, one after another. Only the shell reads them.
  public var requests: @Sendable () -> AsyncStream<Permission> = { .finished }
}

extension PermissionPage: DependencyKey {
  public static let liveValue = PermissionPage(
    open: { permission in PermissionPageChannel.shared.send(permission) },
    requests: { PermissionPageChannel.shared.requests() }
  )

  public static let testValue = PermissionPage()
}

extension DependencyValues {
  public var permissionPage: PermissionPage {
    get { self[PermissionPage.self] }
    set { self[PermissionPage.self] = newValue }
  }
}

/// Carries `PermissionPage` requests from features to the shell. Every listener gets every request from the moment it
/// listens; while nobody listens, the latest request waits for the first listener.
final class PermissionPageChannel: Sendable {
  static let shared = PermissionPageChannel()

  private struct State {
    var listeners: [UUID: AsyncStream<Permission>.Continuation] = [:]
    var waiting: Permission?
  }

  private let state = LockIsolated(State())

  func send(_ permission: Permission) {
    state.withValue { state in
      guard !state.listeners.isEmpty else {
        state.waiting = permission
        return
      }
      for listener in state.listeners.values {
        listener.yield(permission)
      }
    }
  }

  func requests() -> AsyncStream<Permission> {
    let (stream, continuation) = AsyncStream.makeStream(of: Permission.self)
    let id = UUID()
    continuation.onTermination = { [state] _ in
      state.withValue { _ = $0.listeners.removeValue(forKey: id) }
    }
    state.withValue { state in
      if let waiting = state.waiting {
        continuation.yield(waiting)
        state.waiting = nil
      }
      state.listeners[id] = continuation
    }
    return stream
  }
}
