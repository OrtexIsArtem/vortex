import AppKit
import ComposableArchitecture

/// An app as Vortex remembers it: where something was copied, which apps the clipboard ignores.
public struct AppInfo: Codable, Hashable, Sendable {
  public var bundleID: String
  public var name: String

  public init(bundleID: String, name: String) {
    self.bundleID = bundleID
    self.name = name
  }
}

/// What can be on the pasteboard, in the forms Vortex keeps.
public enum PasteboardContent: Codable, Hashable, Sendable {
  case text(String)
  /// A web address copied on its own.
  case link(URL)
  /// PNG data of an image copied without a file: a screenshot, an image from a browser.
  case image(Data)
  /// Files and folders, copied in Finder or another app.
  case files([URL])
}

/// One copy the user made in some app.
public struct PasteboardCopy: Equatable, Sendable {
  public var content: PasteboardContent
  /// The app that copied it marked it secret, as password managers do.
  public var isConcealed: Bool
  /// The app it was copied in, when known.
  public var source: AppInfo?
  /// Bundle ids of the apps that were in front since the previous check, the source among them. Apps rarely say
  /// where a copy comes from, so it may come from any of these.
  public var frontApps: Set<String>

  public init(content: PasteboardContent, isConcealed: Bool = false, source: AppInfo? = nil, frontApps: Set<String> = []) {
    self.content = content
    self.isConcealed = isConcealed
    self.source = source
    self.frontApps = frontApps
  }
}

/// The general pasteboard: copies made in any app, and writing to it.
@DependencyClient
public struct PasteboardClient: Sendable {
  /// Every copy made from now on. macOS does not announce copies, so the pasteboard is checked twice a second
  /// while the stream is alive. Skips what Vortex wrote itself and what apps mark as transient.
  public var copies: @Sendable () -> AsyncStream<PasteboardCopy> = { .finished }
  /// Puts content back on the pasteboard, marked with the app it came from; `isConcealed` asks other clipboard
  /// managers to hide it, as the source app did.
  public var write: @Sendable (_ content: PasteboardContent, _ isConcealed: Bool, _ source: AppInfo?) async -> Void
}

extension PasteboardClient: DependencyKey {
  public static let liveValue = PasteboardClient(
    copies: {
      AsyncStream { continuation in
        let watcher = PasteboardWatcher(pasteboard: .general) { continuation.yield($0) }
        continuation.onTermination = { _ in watcher.stop() }
        watcher.start()
      }
    },
    write: { content, isConcealed, source in
      PasteboardFormat.write(content, isConcealed: isConcealed, source: source, to: .general)
    }
  )

  public static let testValue = PasteboardClient()
}

extension DependencyValues {
  public var pasteboardClient: PasteboardClient {
    get { self[PasteboardClient.self] }
    set { self[PasteboardClient.self] = newValue }
  }
}

/// Checks the pasteboard's change count twice a second on a background queue and reads what changed.
final class PasteboardWatcher: @unchecked Sendable {
  private let queue = DispatchQueue(label: "io.github.ortexisartem.vortex.pasteboard", qos: .utility)
  private let pasteboard: NSPasteboard
  private let onCopy: @Sendable (PasteboardCopy) -> Void
  /// Apps activated since the previous check; filled on the main thread, read on `queue`.
  private let activatedApps = LockIsolated<Set<String>>([])
  // Touched only on `queue`.
  private var timer: DispatchSourceTimer?
  private var activationObserver: (any NSObjectProtocol)?
  private var changeCount = 0

  init(pasteboard: NSPasteboard, onCopy: @escaping @Sendable (PasteboardCopy) -> Void) {
    self.pasteboard = pasteboard
    self.onCopy = onCopy
  }

  func start() {
    queue.async { [self] in
      changeCount = pasteboard.changeCount
      activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification,
        object: nil,
        queue: nil
      ) { [activatedApps] notification in
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let id = app?.bundleIdentifier {
          activatedApps.withValue { _ = $0.insert(id) }
        }
      }
      let timer = DispatchSource.makeTimerSource(queue: queue)
      timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500), leeway: .milliseconds(100))
      timer.setEventHandler { [weak self] in self?.check() }
      timer.resume()
      self.timer = timer
    }
  }

  func stop() {
    queue.async { [self] in
      timer?.cancel()
      timer = nil
      if let activationObserver {
        NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
      }
      activationObserver = nil
    }
  }

  private func check() {
    let count = pasteboard.changeCount
    guard count != changeCount else { return }
    if PasteboardFormat.isOwnWrite(pasteboard, changeCount: count) {
      changeCount = count
      return
    }
    // An app clears the pasteboard, then writes: until it has written, look again next time.
    guard pasteboard.types?.isEmpty == false else { return }
    changeCount = count
    var frontApps = activatedApps.withValue { apps in
      defer { apps = [] }
      return apps
    }
    if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
      frontApps.insert(front)
    }
    if let copy = PasteboardFormat.read(pasteboard, frontApps: frontApps) {
      onCopy(copy)
    }
  }
}

/// How content maps to pasteboard types, following the conventions of nspasteboard.org.
enum PasteboardFormat {
  static let concealedTypes: [NSPasteboard.PasteboardType] = [
    .init("org.nspasteboard.ConcealedType"),
    .init("com.agilebits.onepassword"),
  ]
  /// Snippets text expanders put on the pasteboard for a moment, and other content not meant for a history.
  static let transientTypes: [NSPasteboard.PasteboardType] = [
    .init("org.nspasteboard.TransientType"),
    .init("org.nspasteboard.AutoGeneratedType"),
    .init("de.petermaurer.TransientPasteboardType"),
    .init("com.typeit4me.clipping"),
    .init("Pasteboard generator type"),
  ]
  /// Bundle id of the app the content comes from, when it says so.
  static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
  static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init("public.jpeg"), .init("public.heic")]
  /// Larger copies are not kept.
  static let maxTextBytes = 2_000_000
  static let maxImageBytes = 30_000_000

  /// Change counts of pasteboards right after Vortex wrote to them.
  private static let ownChangeCounts = LockIsolated<[NSPasteboard.Name: Int]>([:])
  /// Keeps the TIFF provider of the last image Vortex wrote until the pasteboard is done with it.
  fileprivate static let tiffProvider = LockIsolated<TIFFProvider?>(nil)

  static func isOwnWrite(_ pasteboard: NSPasteboard, changeCount: Int) -> Bool {
    ownChangeCounts.value[pasteboard.name] == changeCount
  }

  static func read(_ pasteboard: NSPasteboard, frontApps: Set<String> = []) -> PasteboardCopy? {
    guard let types = pasteboard.types, !types.isEmpty, !types.contains(where: transientTypes.contains),
          let content = content(of: pasteboard, types: types)
    else { return nil }
    let source = source(bundleID: pasteboard.string(forType: sourceType))
    return PasteboardCopy(
      content: content,
      isConcealed: types.contains(where: concealedTypes.contains),
      source: source,
      frontApps: frontApps.union(source.map { [$0.bundleID] } ?? [])
    )
  }

  /// Files first: Finder also puts the file icon as an image and the name as text. Then text, unless it is only
  /// the address of an image copied in a browser. Then the image, then a link.
  static func content(of pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> PasteboardContent? {
    let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
    if let fileURLs, !fileURLs.isEmpty {
      return .files(fileURLs)
    }
    let string = pasteboard.string(forType: .string)
    let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let typedLink = webLink(trimmed)
    if let string, !trimmed.isEmpty, typedLink == nil {
      return string.utf8.count <= maxTextBytes ? .text(string) : nil
    }
    if types.contains(where: imageTypes.contains), let png = pngData(pasteboard) {
      return .image(png)
    }
    let link = typedLink ?? (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first { !$0.isFileURL }
    return link.map(PasteboardContent.link)
  }

  /// A single http or https address, nothing else.
  static func webLink(_ text: String) -> URL? {
    guard !text.isEmpty, !text.contains(where: \.isWhitespace),
          let url = URL(string: text), let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https", url.host?.isEmpty == false
    else { return nil }
    return url
  }

  private static func pngData(_ pasteboard: NSPasteboard) -> Data? {
    if let png = pasteboard.data(forType: .png) {
      return png.count <= maxImageBytes ? png : nil
    }
    for type in imageTypes.dropFirst() {
      guard let data = pasteboard.data(forType: type) else { continue }
      guard data.count <= maxImageBytes * 4 else { return nil }
      let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
      return png.flatMap { $0.count <= maxImageBytes ? $0 : nil }
    }
    return nil
  }

  /// The app that says it wrote the content; otherwise the app in front, which is where almost every copy comes from.
  private static func source(bundleID: String?) -> AppInfo? {
    if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
      let name = FileManager.default.displayName(atPath: url.path)
      return AppInfo(bundleID: bundleID, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
    }
    guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier else { return nil }
    return AppInfo(bundleID: id, name: app.localizedName ?? id)
  }

  /// Writes one pasteboard item per file, or a single item, with every type and marker at once, so a reader never
  /// sees the content without its markers. The source marker names the app the content first came from.
  static func write(_ content: PasteboardContent, isConcealed: Bool, source: AppInfo?, to pasteboard: NSPasteboard) {
    var items: [NSPasteboardItem] = []
    switch content {
    case let .text(text):
      let item = NSPasteboardItem()
      item.setString(text, forType: .string)
      items = [item]
    case let .link(url):
      let item = NSPasteboardItem()
      item.setString(url.absoluteString, forType: .URL)
      item.setString(url.absoluteString, forType: .string)
      items = [item]
    case let .image(png):
      let item = NSPasteboardItem()
      item.setData(png, forType: .png)
      // Older apps read only TIFF. Making it from a large image takes half a second, so it is made on request.
      let provider = TIFFProvider(png: png)
      tiffProvider.setValue(provider)
      item.setDataProvider(provider, forTypes: [.tiff])
      items = [item]
    case let .files(urls):
      items = urls.map { url in
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        return item
      }
    }
    items.first?.setString(source?.bundleID ?? ownBundleID, forType: sourceType)
    if isConcealed {
      items.first?.setData(Data(), forType: concealedTypes[0])
    }
    pasteboard.clearContents()
    pasteboard.writeObjects(items)
    let name = pasteboard.name
    let changeCount = pasteboard.changeCount
    ownChangeCounts.withValue { $0[name] = changeCount }
  }

  private static var ownBundleID: String {
    Bundle.main.bundleIdentifier ?? "io.github.ortexisartem.vortex"
  }
}

/// Makes TIFF from PNG when an app asks the pasteboard for it.
private final class TIFFProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
  private let png: Data

  init(png: Data) {
    self.png = png
  }

  func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
    guard type == .tiff, let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation(using: .lzw, factor: 0) else { return }
    item.setData(tiff, forType: .tiff)
  }

  func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
    PasteboardFormat.tiffProvider.withValue { provider in
      if provider === self { provider = nil }
    }
  }
}
