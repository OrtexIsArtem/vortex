import AppKit
import ComposableArchitecture
import CoreServices
import VortexCore

/// What Vortex needs to know about a file or folder it shows.
public struct FileInfo: Equatable, Sendable {
  /// Bytes of a file; nil for folders.
  public var size: Int64?
  public var isDirectory: Bool
  /// A file this user may run (through a link too); false for folders.
  public var isExecutable: Bool

  public init(size: Int64?, isDirectory: Bool, isExecutable: Bool = false) {
    self.size = size
    self.isDirectory = isDirectory
    self.isExecutable = isExecutable
  }
}

/// Files and folders on disk.
@DependencyClient
public struct FileClient: Sendable {
  /// Size and kind of what is at the URL right now; nil when nothing is there.
  public var info: @Sendable (_ url: URL) async -> FileInfo?
  /// What a folder holds, without hidden files; empty when the folder is missing.
  public var contents: @Sendable (_ folder: URL) async -> [URL] = { _ in [] }
  public var read: @Sendable (_ url: URL) async throws -> Data
  /// Writes the data, creating missing folders.
  public var write: @Sendable (_ data: Data, _ url: URL) async throws -> Void
  /// Copies a file or folder, creating missing folders.
  public var copy: @Sendable (_ from: URL, _ to: URL) async throws -> Void
  /// Deletes a file or folder for good; does nothing when it is already gone.
  public var remove: @Sendable (_ url: URL) async -> Void
  /// Opens Finder with the items selected.
  public var revealInFinder: @Sendable (_ urls: [URL]) async -> Void
  /// Opens a file in its app, or a web address in the browser.
  public var open: @Sendable (_ url: URL) async -> Void
  /// Asks the user to pick a folder; nil when they cancel.
  public var chooseFolder: @Sendable () async -> URL?
  /// Files created, changed or renamed inside the folder and its subfolders, as the system reports them, and the
  /// files of a folder moved in, with paths that start with the folder as given. Hidden files and folders, and
  /// whatever sits inside packages (apps, partial Safari downloads) are left out. A file being written may be
  /// reported several times. Ending the stream stops watching.
  public var changes: @Sendable (_ folder: URL) -> AsyncStream<URL> = { _ in .finished }
}

extension FileClient: DependencyKey {
  public static let liveValue = FileClient(
    info: { url in
      // Not `URL.resourceValues`: it caches inside the URL, and a file deleted later would still look present.
      let path = url.resolvingSymlinksInPath().path
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
      let size = isDirectory.boolValue ? nil : (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int64
      return FileInfo(
        size: size,
        isDirectory: isDirectory.boolValue,
        isExecutable: !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
      )
    },
    contents: { folder in
      (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
    },
    read: { url in
      try Data(contentsOf: url)
    },
    write: { data, url in
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
    },
    copy: { from, to in
      try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: from, to: to)
    },
    remove: { url in
      try? FileManager.default.removeItem(at: url)
    },
    revealInFinder: { urls in
      await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    },
    open: { url in
      await MainActor.run { _ = NSWorkspace.shared.open(url) }
    },
    chooseFolder: {
      await withCheckedContinuation { continuation in
        Task { @MainActor in
          let panel = NSOpenPanel()
          panel.canChooseDirectories = true
          panel.canChooseFiles = false
          panel.canCreateDirectories = true
          panel.allowsMultipleSelection = false
          // Vortex has no Dock icon and its window floats above the menu bar: lift the panel over it.
          panel.level = .aboveVortex
          NSApp.activate()
          OutsideActivity.shared.begin()
          panel.begin { response in
            OutsideActivity.shared.end()
            continuation.resume(returning: response == .OK ? panel.url : nil)
          }
        }
      }
    },
    changes: { folder in
      AsyncStream { continuation in
        let watcher = FolderWatcher(folder: folder) { continuation.yield($0) }
        continuation.onTermination = { _ in watcher.stop() }
        if !watcher.start() {
          continuation.finish()
        }
      }
    }
  )

  public static let testValue = FileClient()
}

extension DependencyValues {
  public var fileClient: FileClient {
    get { self[FileClient.self] }
    set { self[FileClient.self] = newValue }
  }
}

/// Reports changed files under a folder through FSEvents, on a background queue.
private final class FolderWatcher: @unchecked Sendable {
  /// Files of a folder moved in that are reported at most; more would be someone moving a whole project in.
  private static let maxFilesPerFolder = 1_000
  private let folder: URL
  private let onChange: @Sendable (URL) -> Void
  private let queue = DispatchQueue(label: "io.github.ortexisartem.vortex.folder-watcher", qos: .utility)
  /// The watched folder as FSEvents spells paths, with symbolic links resolved.
  private let root: String
  /// The watched folder as the caller gave it; reported paths start with it.
  private let given: String
  /// Set once by `start`, then touched only on `queue`.
  private var stream: FSEventStreamRef?

  init(folder: URL, onChange: @escaping @Sendable (URL) -> Void) {
    self.folder = folder
    self.onChange = onChange
    root = folder.resolvingSymlinksInPath().path
    given = folder.path
  }

  /// False when the folder can't be watched, for example when it does not exist.
  func start() -> Bool {
    var context = FSEventStreamContext(
      version: 0,
      info: Unmanaged.passUnretained(self).toOpaque(),
      retain: nil,
      release: nil,
      copyDescription: nil
    )
    let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
      guard let info else { return }
      let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
      let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
      for index in 0..<min(count, paths.count) {
        watcher.handle(path: paths[index], flags: flags[index])
      }
    }
    let flags = FSEventStreamCreateFlags(
      kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
    )
    guard FileManager.default.fileExists(atPath: folder.path),
          let stream = FSEventStreamCreate(
            nil, callback, &context, [folder.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags
          )
    else { return false }
    FSEventStreamSetDispatchQueue(stream, queue)
    guard FSEventStreamStart(stream) else {
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      return false
    }
    self.stream = stream
    return true
  }

  private func handle(path: String, flags: FSEventStreamEventFlags) {
    let isFile = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0
    let isFolder = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0
    let changed = flags & FSEventStreamEventFlags(
      kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemRenamed
    ) != 0
    guard changed, isFile || isFolder, !isHiddenOrPackaged(path) else { return }
    let url = URL(fileURLWithPath: path.hasPrefix(root + "/") ? given + path.dropFirst(root.count) : path)
    if isFile {
      onChange(url)
      return
    }
    // A folder moved in brings files the system reports nothing about.
    guard let files = FileManager.default.enumerator(
      at: url,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else { return }
    var reported = 0
    for case let file as URL in files where reported < Self.maxFilesPerFolder {
      guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
      onChange(file)
      reported += 1
    }
  }

  /// Whether the path, below the watched folder, is hidden or inside a package such as an app or a `.download`.
  private func isHiddenOrPackaged(_ path: String) -> Bool {
    guard path.hasPrefix(root + "/") else { return false }
    var partial = root
    let components = path.dropFirst(root.count + 1).split(separator: "/")
    for (index, component) in components.enumerated() {
      if component.hasPrefix(".") { return true }
      partial += "/" + component
      let isLast = index == components.count - 1
      if !isLast, (try? URL(fileURLWithPath: partial).resourceValues(forKeys: [.isPackageKey]))?.isPackage == true {
        return true
      }
    }
    return false
  }

  func stop() {
    // On the queue, after any callback in flight; the block keeps the watcher alive until the stream is gone.
    queue.async { [self] in
      guard let stream else { return }
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
      self.stream = nil
    }
  }
}
