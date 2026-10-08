import ComposableArchitecture
import Foundation
import LocalAuthentication

/// The owner of the Mac confirming it is them: Touch ID, or their password where there is no Touch ID.
@DependencyClient
public struct AuthenticationClient: Sendable {
  /// Asks for Touch ID or the password, saying `reason` in the system's prompt; true once the owner confirmed.
  public var confirmOwner: @Sendable (_ reason: String) async -> Bool = { _ in false }
}

extension AuthenticationClient: DependencyKey {
  public static let liveValue = AuthenticationClient(
    confirmOwner: { reason in
      let context = LAContext()
      var error: NSError?
      guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
      return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
  )

  public static let testValue = AuthenticationClient()
}

extension DependencyValues {
  public var authenticationClient: AuthenticationClient {
    get { self[AuthenticationClient.self] }
    set { self[AuthenticationClient.self] = newValue }
  }
}
