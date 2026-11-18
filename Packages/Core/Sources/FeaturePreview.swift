import Foundation

/// What a feature's page in the catalog shows on top: a short looping video without sound, and a still for Reduce
/// Motion and while the video loads. Both are files in the feature's own bundle, under `Resources/Catalog/`.
public struct FeaturePreview: Equatable, Sendable {
  public var video: URL?
  public var still: URL?

  public init(video: URL? = nil, still: URL? = nil) {
    self.video = video
    self.still = still
  }
}
