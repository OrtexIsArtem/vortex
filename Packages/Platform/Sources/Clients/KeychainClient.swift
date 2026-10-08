import ComposableArchitecture
import Foundation
import Security

/// Secrets in the login keychain: one generic password per account, under a service of the caller's own. Vortex
/// created them, so it reads them without asking; Keychain Access shows them by their label.
@DependencyClient
public struct KeychainClient: Sendable {
  /// Stores `value` under `account`, replacing what was there.
  public var save: @Sendable (_ service: String, _ account: String, _ value: String, _ label: String) async throws -> Void
  /// The value under `account`; nil when there is none.
  public var read: @Sendable (_ service: String, _ account: String) async throws -> String?
  public var delete: @Sendable (_ service: String, _ account: String) async -> Void
  /// Every account the service keeps, to find values whose owner is gone.
  public var accounts: @Sendable (_ service: String) async -> [String] = { _ in [] }
}

/// A keychain call failed with this status.
public struct KeychainError: Error, Equatable {
  public let status: OSStatus

  public init(status: OSStatus) {
    self.status = status
  }
}

extension KeychainClient: DependencyKey {
  public static let liveValue = KeychainClient(
    save: { service, account, value, label in try Keychain.save(value, service: service, account: account, label: label) },
    read: { service, account in try Keychain.read(service: service, account: account) },
    delete: { service, account in Keychain.delete(service: service, account: account) },
    accounts: { service in Keychain.accounts(service: service) }
  )

  public static let testValue = KeychainClient()
}

extension DependencyValues {
  public var keychainClient: KeychainClient {
    get { self[KeychainClient.self] }
    set { self[KeychainClient.self] = newValue }
  }
}

/// The calls themselves; they may wait for the keychain, so they run off the main thread.
private enum Keychain {
  static func item(service: String, account: String) -> [CFString: Any] {
    [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
  }

  static func save(_ value: String, service: String, account: String, label: String) throws {
    let data = Data(value.utf8)
    let query = item(service: service, account: account)
    let update: [CFString: Any] = [kSecValueData: data, kSecAttrLabel: label]
    let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      let added = SecItemAdd(query.merging(update) { $1 } as CFDictionary, nil)
      guard added == errSecSuccess else { throw KeychainError(status: added) }
    } else if status != errSecSuccess {
      throw KeychainError(status: status)
    }
  }

  static func read(service: String, account: String) throws -> String? {
    var query = item(service: service, account: account)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
    return String(decoding: data, as: UTF8.self)
  }

  static func delete(service: String, account: String) {
    SecItemDelete(item(service: service, account: account) as CFDictionary)
  }

  static func accounts(service: String) -> [String] {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecReturnAttributes: true,
      kSecMatchLimit: kSecMatchLimitAll,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let items = result as? [[CFString: Any]]
    else { return [] }
    return items.compactMap { $0[kSecAttrAccount] as? String }
  }
}
