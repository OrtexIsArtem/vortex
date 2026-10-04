import AppKit
import ComposableArchitecture
import CoreServices
import VortexCore

/// What Vortex needs to know about a file or folder it shows.
public struct FileInfo: Equatable, Sendable {
  /// Bytes of a file; nil for folders.
  public var size: Int64?
  public var isDirectory: Bool

  public init(size: Int64?, isDirectory: Bool) {
    self.size = size
    self.isDirectory = isDirectory
  }
}

/// Files and folders on disk.
@DependencyClient
public struct FileClient: Sendable {
  /// Size and kind of what is at the URL; nil when nothing is there.
  public var info: @Sendable (_ url: URL) async -> FileInfo?
  public var read: @Sendable (_ url: URL) async throws -> Data
  /// Writes the data, creating missing folders.
  public var write: @Sendable (_ data: Data, _ url: URL) async throws -> Void
  /// Copies a file or folder, creating missing folders.
  public var copy: @Sendable (_ from: URL, _ to: URL) async throws -> Void
  /// Deletes a file or folder for good; does nothing when it is already gone.
  public var remove: @Sendable (_ url: URL) async -> Void
  /// Opens Finder with the items selected.
  public var revealInFinder: @Sendable (_ urls: [URL]) async -> Void
  /// Asks the user to pick a folder; nil when they cancel.
  public var chooseFolder: @Sendable () async -> URL?
  /// Files created, changed or renamed inside the folder and its subfolders, as the system reports them.
  /// A file being written is reported several times. Ending the stream stops watching.
  public var changes: @Sendable (_ folder: URL) -> AsyncStream<URL> = { _ in .finished }
}

extension FileClient: DependencyKey {
  public static let liveValue = FileClient(
    info: { url in
      guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else { return nil }
      let isDirectory = values.isDirectory ?? false
      return FileInfo(size: isDirectory ? nil : values.fileSize.map(Int64.init), isDirectory: isDirectory)
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
          panel.begin { response in
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
  private let folder: URL
  private let onChange: @Sendable (URL) -> Void
  private let queue = DispatchQueue(label: "io.github.ortexisartem.vortex.folder-watcher", qos: .utility)
  /// Set once by `start`, then touched only on `queue`.
  private var stream: FSEventStreamRef?

  init(folder: URL, onChange: @escaping @Sendable (URL) -> Void) {
    self.folder = folder
    self.onChange = onChange
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
      let interesting = FSEventStreamEventFlags(
        kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemRenamed
      )
      for index in 0..<min(count, paths.count) {
        let flag = flags[index]
        guard flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0, flag & interesting != 0 else { continue }
        watcher.onChange(URL(fileURLWithPath: paths[index]))
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
