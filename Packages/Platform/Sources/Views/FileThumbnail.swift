import AppKit
import QuickLookThumbnailing
import SwiftUI

/// A picture of a file's content (an image, a PDF page, a video frame) made by Quick Look in the background.
/// Shows `placeholder` while it is made and for files that have no such picture.
public struct FileThumbnail<Placeholder: View>: View {
  private let url: URL
  private let size: CGSize
  private let placeholder: Placeholder
  @State private var thumbnail: NSImage?
  @Environment(\.displayScale) private var displayScale

  public init(url: URL, size: CGSize, @ViewBuilder placeholder: () -> Placeholder) {
    self.url = url
    self.size = size
    self.placeholder = placeholder()
  }

  public var body: some View {
    Group {
      if let thumbnail {
        // Fills the space it is given without asking for more: a picture wider than its frame is cut at the sides
        // instead of widening the frame over its neighbours.
        Color.clear
          .overlay {
            Image(nsImage: thumbnail)
              .resizable()
              .aspectRatio(contentMode: .fill)
          }
          .clipped()
      } else {
        placeholder
      }
    }
    .task(id: url) {
      thumbnail = await ThumbnailCache.shared.thumbnail(for: url, size: size, scale: displayScale)
    }
  }
}

/// The Finder icon of a file or folder.
public struct FileIcon: View {
  private let url: URL

  public init(url: URL) {
    self.url = url
  }

  public var body: some View {
    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
      .resizable()
      .interpolation(.high)
      .aspectRatio(contentMode: .fit)
      .accessibilityHidden(true)
  }
}

/// A file's or folder's name as Finder shows it in the app's language, when it differs by more than a hidden
/// extension: a folder or app macOS names in that language, such as Downloads; otherwise its name on disk, extension
/// included.
public enum FileName {
  public static func shown(_ url: URL) -> String {
    let name = url.lastPathComponent
    let shown = FileManager.default.displayName(atPath: url.path)
    // Finder may hide an extension too; Vortex always shows it, as a build's .ipa or .aab matters.
    return shown.isEmpty || shown == url.deletingPathExtension().lastPathComponent ? name : shown
  }
}

/// Thumbnails already made, so scrolling and reopening the window do not make them again.
private actor ThumbnailCache {
  static let shared = ThumbnailCache()
  private let cache = NSCache<NSString, NSImage>()

  func thumbnail(for url: URL, size: CGSize, scale: CGFloat) async -> NSImage? {
    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    let key = "\(url.path)|\(Int(size.width))x\(Int(size.height))@\(scale)|\(modified?.timeIntervalSince1970 ?? 0)" as NSString
    if let image = cache.object(forKey: key) { return image }
    let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
    guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
      return nil
    }
    let image = representation.nsImage
    cache.setObject(image, forKey: key)
    return image
  }
}
