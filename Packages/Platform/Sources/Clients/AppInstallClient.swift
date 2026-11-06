import ComposableArchitecture
import Foundation

/// A version of Vortex: CFBundleShortVersionString and CFBundleVersion.
public struct AppVersion: Equatable, Sendable {
  /// "0.1.2": what Settings shows.
  public var short: String
  /// The build number; every release build has one of its own.
  public var build: String

  public init(short: String, build: String) {
    self.short = short
    self.build = build
  }

  /// The version in a bundle's Info.plist; empty where it has none, as under `swift test`.
  public init(bundle: Bundle) {
    short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? ""
  }

  /// This app's version.
  public static var current: AppVersion { AppVersion(bundle: .main) }

  /// "0.1.2 (17)": the short version and the build.
  public var full: String { "\(short) (\(build))" }

  /// Whether `version` is newer than `other`, compared as numbers between the dots: 0.1.10 is newer than 0.1.9, and
  /// 1.0 is the same as 1.0.0. Whatever follows the digits of a part doesn't count.
  public static func isNewer(_ version: String, than other: String) -> Bool {
    let lhs = numbers(version)
    let rhs = numbers(other)
    for index in 0..<max(lhs.count, rhs.count) {
      let left = index < lhs.count ? lhs[index] : 0
      let right = index < rhs.count ? rhs[index] : 0
      if left != right { return left > right }
    }
    return false
  }

  private static func numbers(_ version: String) -> [Int] {
    version.split(separator: ".", omittingEmptySubsequences: false).map { part in
      Int(part.prefix { $0.isASCII && $0.isNumber }) ?? 0
    }
  }
}

/// This copy of Vortex, as it runs.
public struct AppCopy: Equatable, Sendable {
  /// The bundle that runs: under App Translocation, a read-only copy at a random path.
  public var bundle: URL
  /// The bundle the user opened, when App Translocation runs a copy of it and macOS tells where it is; nil otherwise.
  public var original: URL?
  /// App Translocation runs this copy: macOS does that to a quarantined app opened where it was downloaded.
  public var isTranslocated: Bool
  public var bundleID: String
  /// CFBundleShortVersionString.
  public var version: String

  public init(bundle: URL, original: URL? = nil, isTranslocated: Bool = false, bundleID: String, version: String) {
    self.bundle = bundle
    self.original = original
    self.isTranslocated = isTranslocated
    self.bundleID = bundleID
    self.version = version
  }

  /// Where the user keeps this copy: the original of a translocated copy, else the bundle itself.
  public var location: URL { original ?? bundle }
}

/// An app on disk, as its Info.plist says.
public struct InstalledApp: Equatable, Sendable {
  public var bundleID: String?
  /// CFBundleShortVersionString.
  public var version: String?

  public init(bundleID: String?, version: String?) {
    self.bundleID = bundleID
    self.version = version
  }

  /// What is at `url`; nil when nothing is there. Read from the file, never from `Bundle`, which keeps what it read
  /// once for a path.
  init?(at url: URL) {
    guard (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil else { return nil }
    let plist = url.appending(path: "Contents/Info.plist")
    let info = (try? Data(contentsOf: plist))
      .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
    bundleID = info?["CFBundleIdentifier"] as? String
    version = info?["CFBundleShortVersionString"] as? String
  }
}

/// Where this copy of Vortex runs from, the app at a path, and moving this copy to /Applications, which release builds
/// offer at launch (the shell's MoveToApplications).
@DependencyClient
public struct AppInstallClient: Sendable {
  /// This copy: the bundle that runs and, under App Translocation, the original macOS runs it from.
  public var current: @Sendable () -> AppCopy?
  /// The app at `url`; nil when nothing is there.
  public var app: @Sendable (_ url: URL) -> InstalledApp?
  /// Puts this copy at `destination`. The app there goes to the Trash first, whole, and is never written into: when it
  /// can't go, nothing changes. Then this copy lands there: renamed on the same volume; copied from another volume, or
  /// from the translocated path when macOS doesn't tell where the original is (the source then goes to the Trash if it
  /// can). The quarantine attribute comes off, so macOS doesn't translocate it again. Throws on any failure, macOS's
  /// App Management refusing (EPERM) included, with nothing half-done: a partial copy goes, and an app it moved to the
  /// Trash comes back.
  public var move: @Sendable (_ copy: AppCopy, _ destination: URL) throws -> Void
  /// "Don't ask again" was ticked with Not Now.
  public var isMoveDeclined: @Sendable () -> Bool = { false }
  /// Remembers "Don't ask again"; release builds only.
  public var declineMove: @Sendable () -> Void
}

extension AppInstallClient: DependencyKey {
  public static let liveValue: AppInstallClient = {
    let declinedKey = "moveToApplicationsDeclined"
    return AppInstallClient(
      current: {
        let bundle = Bundle.main.bundleURL
        let translocation = Translocation.original(of: bundle)
        return AppCopy(
          bundle: bundle,
          original: translocation.original,
          isTranslocated: translocation.isTranslocated,
          bundleID: Bundle.main.bundleIdentifier ?? "",
          version: AppVersion.current.short
        )
      },
      app: { url in InstalledApp(at: url) },
      move: { copy, destination in try AppMover.live.move(copy, to: destination) },
      isMoveDeclined: { UserDefaults.standard.bool(forKey: declinedKey) },
      declineMove: {
        #if !DEBUG
          UserDefaults.standard.set(true, forKey: declinedKey)
        #endif
      }
    )
  }()

  public static let testValue = AppInstallClient()
}

extension DependencyValues {
  public var appInstallClient: AppInstallClient {
    get { self[AppInstallClient.self] }
    set { self[AppInstallClient.self] = newValue }
  }
}

/// App Translocation: macOS runs a quarantined app opened where it was downloaded from a random read-only path. Security
/// tells the original's path through functions missing from its public headers, so they are looked up at runtime, as
/// LetsMove does; without them nothing is translocated as far as Vortex can tell.
enum Translocation {
  private typealias IsTranslocatedURL = @convention(c) (
    CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?
  ) -> DarwinBoolean
  private typealias CreateOriginalPathForURL = @convention(c) (
    CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?
  ) -> Unmanaged<CFURL>?

  /// Whether `bundle` runs translocated, and the original's URL when Security tells it.
  static func original(of bundle: URL) -> (isTranslocated: Bool, original: URL?) {
    guard let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY) else {
      return (false, nil)
    }
    defer { dlclose(security) }
    guard let isTranslocatedSymbol = dlsym(security, "SecTranslocateIsTranslocatedURL") else { return (false, nil) }
    let isTranslocatedURL = unsafeBitCast(isTranslocatedSymbol, to: IsTranslocatedURL.self)
    var isTranslocated = false
    guard isTranslocatedURL(bundle as CFURL, &isTranslocated, nil).boolValue, isTranslocated else { return (false, nil) }
    guard let originalSymbol = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else { return (true, nil) }
    let createOriginalPath = unsafeBitCast(originalSymbol, to: CreateOriginalPathForURL.self)
    let original = createOriginalPath(bundle as CFURL, nil)?.takeRetainedValue()
    return (true, original.map { $0 as URL })
  }
}

/// The file steps of the move, on any folders: tests run them on temporary ones that stand in for /Applications and the
/// Trash. Only whole bundles are moved: the app already there is never written into.
struct AppMover: Sendable {
  /// Moves an item, whole, to the Trash, and tells where it went; nil when macOS doesn't say.
  var trash: @Sendable (_ url: URL) throws -> URL?

  static let live = AppMover { url in
    var trashed: NSURL?
    try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
    return trashed as URL?
  }

  /// Moves `copy` from where the user keeps it. Only App Translocation's read-only path, when macOS doesn't tell where
  /// the original is, has to be copied, and that path never goes to the Trash.
  func move(_ copy: AppCopy, to destination: URL) throws {
    let onlyTranslocated = copy.isTranslocated && copy.original == nil
    try install(copy.location, at: destination, copying: onlyTranslocated, trashesCopiedSource: !onlyTranslocated)
  }

  /// The app at `destination` goes to the Trash first: when it can't, this throws before anything changed. Then `source`
  /// lands there, renamed, or copied when `copying` or when it is on another volume; a copied source goes to the Trash
  /// afterwards if `trashesCopiedSource` and it can, as nothing should stay behind. On a failure a partial copy goes and
  /// the old app comes back from the Trash. Last, the quarantine attribute comes off the new app, if it can.
  func install(_ source: URL, at destination: URL, copying: Bool = false, trashesCopiedSource: Bool = true) throws {
    let files = FileManager.default
    // `attributesOfItem` doesn't follow a link: a link there counts as something there.
    let trashed = (try? files.attributesOfItem(atPath: destination.path)) != nil ? try trash(destination) : nil
    func putBack() {
      if let trashed { try? files.moveItem(at: trashed, to: destination) }
    }
    let copies: Bool
    do {
      // A rename happens whole or not at all: a failed one leaves nothing to remove.
      copies = try copying || !rename(source, to: destination)
    } catch {
      putBack()
      throw error
    }
    if copies {
      do {
        try files.copyItem(at: source, to: destination)
      } catch {
        // A copy may stop halfway; what it left is ours to remove.
        try? files.removeItem(at: destination)
        putBack()
        throw error
      }
    }
    Self.removeQuarantine(destination)
    if copies, trashesCopiedSource { _ = try? trash(source) }
  }

  /// Renames `source` to `destination`, whole: true when it did, false when they are on different volumes, which a
  /// rename can't cross. Throws on any other failure.
  private func rename(_ source: URL, to destination: URL) throws -> Bool {
    // The error number is read at once, before anything else can change it.
    let code: Int32 = source.withUnsafeFileSystemRepresentation { from in
      destination.withUnsafeFileSystemRepresentation { to in
        guard let from, let to else { return EINVAL }
        return Darwin.rename(from, to) == 0 ? 0 : errno
      }
    }
    if code == 0 { return true }
    guard code != EXDEV else { return false }
    throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
  }

  /// Takes the quarantine attribute off a bundle and everything in it; what can't be changed is left as it is.
  static func removeQuarantine(_ bundle: URL) {
    let root = bundle.path
    var paths = [root]
    if let items = FileManager.default.enumerator(atPath: root) {
      for case let item as String in items {
        paths.append(root + "/" + item)
      }
    }
    for path in paths {
      removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW)
    }
  }
}
