import AppKit
import ComposableArchitecture
import Quartz
import VortexCore

/// The system Quick Look panel for files shown in Vortex.
@DependencyClient
public struct QuickLookClient: Sendable {
  /// Shows the files in Quick Look, or closes it when it already shows them.
  public var toggle: @Sendable (_ urls: [URL]) async -> Void
  public var close: @Sendable () async -> Void
}

extension QuickLookClient: DependencyKey {
  public static let liveValue = QuickLookClient(
    toggle: { urls in await QuickLook.shared.toggle(urls) },
    close: { await QuickLook.shared.close() }
  )

  public static let testValue = QuickLookClient()
}

extension DependencyValues {
  public var quickLookClient: QuickLookClient {
    get { self[QuickLookClient.self] }
    set { self[QuickLookClient.self] = newValue }
  }
}

/// Feeds the Quick Look panel. The panel finds its controller in the responder chain of the window with keyboard
/// focus, so Vortex windows forward `acceptsPreviewPanelControl`, `beginPreviewPanelControl` and
/// `endPreviewPanelControl` here.
@MainActor
public final class QuickLook: NSObject {
  public static let shared = QuickLook()
  private var urls: [URL] = []

  /// Whether there is something to preview, for `acceptsPreviewPanelControl`.
  public var hasItems: Bool { !urls.isEmpty }

  public func beginControl(_ panel: QLPreviewPanel) {
    panel.dataSource = self
    panel.reloadData()
  }

  public func endControl(_ panel: QLPreviewPanel) {
    panel.dataSource = nil
  }

  func toggle(_ urls: [URL]) {
    guard let panel = QLPreviewPanel.shared() else { return }
    if panel.isVisible, urls == self.urls {
      close()
      return
    }
    self.urls = urls
    guard !urls.isEmpty else { return }
    if panel.isVisible {
      panel.reloadData()
    } else {
      panel.makeKeyAndOrderFront(nil)
    }
    // The Vortex window floats above the menu bar; the panel has to float above it.
    panel.level = .aboveVortex
  }

  func close() {
    guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
    panel.orderOut(nil)
  }
}

extension QuickLook: @preconcurrency QLPreviewPanelDataSource {
  public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
    urls.count
  }

  public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
    urls.indices.contains(index) ? urls[index] as NSURL : nil
  }
}
