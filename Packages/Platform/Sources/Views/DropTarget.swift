import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Something dropped on a Vortex window from another app.
public enum DroppedItem: Equatable, Sendable {
  case file(URL)
  /// PNG data of an image dragged without a file, such as an image from a web page.
  case image(Data)
  case link(URL)
  case text(String)
}

extension View {
  /// Takes files, images, links and text dragged from other apps. `perform` gets them once they are loaded;
  /// `isTargeted` is true while a drag hovers the view.
  public func dropTarget(
    isTargeted: Binding<Bool>? = nil,
    perform: @escaping @MainActor ([DroppedItem]) -> Void
  ) -> some View {
    onDrop(of: DropReader.types, isTargeted: isTargeted) { providers in
      Task { @MainActor in
        let items = await DropReader.items(from: providers)
        if !items.isEmpty { perform(items) }
      }
      return true
    }
  }
}

@MainActor
enum DropReader {
  static let types: [UTType] = [.fileURL, .image, .url, .plainText]
  private static let imageTypes: [UTType] = [.png, .tiff, .jpeg, .heic, .image]

  static func items(from providers: [NSItemProvider]) async -> [DroppedItem] {
    var items: [DroppedItem] = []
    for provider in providers {
      if let item = await item(from: provider) {
        items.append(item)
      }
    }
    return items
  }

  /// A file wins over its icon, an image over its address, a link over its text.
  private static func item(from provider: NSItemProvider) async -> DroppedItem? {
    if let data = await data(of: .fileURL, from: provider),
       let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
      return .file(url)
    }
    for type in imageTypes {
      if let data = await data(of: type, from: provider) {
        let png = type == .png ? data : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
        if let png { return .image(png) }
      }
    }
    if let data = await data(of: .url, from: provider),
       let url = URL(dataRepresentation: data, relativeTo: nil), !url.isFileURL {
      return .link(url)
    }
    if let text = await text(from: provider) {
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      return PasteboardFormat.webLink(trimmed).map(DroppedItem.link) ?? .text(text)
    }
    return nil
  }

  /// Text in whatever encoding the other app offers.
  private static func text(from provider: NSItemProvider) async -> String? {
    guard provider.canLoadObject(ofClass: NSString.self) else { return nil }
    return await withCheckedContinuation { continuation in
      _ = provider.loadObject(ofClass: NSString.self) { object, _ in
        continuation.resume(returning: (object as? NSString).map(String.init))
      }
    }
  }

  private static func data(of type: UTType, from provider: NSItemProvider) async -> Data? {
    guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
    return await withCheckedContinuation { continuation in
      _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
        continuation.resume(returning: data)
      }
    }
  }
}
