import AppKit
import ComposableArchitecture
import CoreImage
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// A picture of a screen or a part of it: an image that never changes, safe to hand between threads.
public struct ScreenImage: @unchecked Sendable, Equatable {
  public let cgImage: CGImage
  /// Pixels per point.
  public let scale: CGFloat

  public init(cgImage: CGImage, scale: CGFloat) {
    self.cgImage = cgImage
    self.scale = scale
  }

  /// An image file, at 1 pixel per point unless `scale` says otherwise; nil when it can't be read.
  public init?(contentsOf url: URL, scale: CGFloat = 1) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    self.init(cgImage: image, scale: scale)
  }

  /// The contents of an image file, decoded here, on the calling thread, so drawing it never waits for that; nil when
  /// it can't be read. Core Image decodes HEIC on the hardware decoder: a whole screen in about 20 ms rather than 140.
  public init?(decoding data: Data, scale: CGFloat = 1) {
    guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
    let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
    guard let decoded = Self.decoder.createCGImage(image, from: image.extent, format: .BGRA8, colorSpace: space) else {
      return nil
    }
    self.init(cgImage: decoded, scale: scale)
  }

  /// Made on first use, which takes a moment; Core Image contexts are safe to use from any thread.
  private static let decoder = CIContext(options: [.cacheIntermediates: false])

  public static func == (lhs: ScreenImage, rhs: ScreenImage) -> Bool {
    lhs.cgImage === rhs.cgImage && lhs.scale == rhs.scale
  }

  /// The size in points.
  public var size: CGSize {
    CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
  }

  /// The part inside `rect`, in points from the top left corner; nil when the rect misses the image.
  public func cropped(to rect: CGRect) -> ScreenImage? {
    let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
      .integral
      .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    guard !pixels.isEmpty, let part = cgImage.cropping(to: pixels) else { return nil }
    return ScreenImage(cgImage: part, scale: scale)
  }

  /// PNG, for parts with text: sharp and small enough.
  public func pngData() -> Data? {
    encoded(as: .png, quality: nil)
  }

  /// HEIC, for whole screens: a fraction of the size of a PNG.
  public func heicData(quality: Double = 0.8) -> Data? {
    encoded(as: .heic, quality: quality)
  }

  private func encoded(as type: UTType, quality: Double?) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
    var properties: [CFString: Any] = [:]
    if let quality { properties[kCGImageDestinationLossyCompressionQuality] = quality }
    CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }
}

/// A whole display as it looked at one moment.
public struct Screenshot: Equatable, Sendable {
  public var image: ScreenImage
  /// The hardware notch, in points from the display's top left corner; nil without one.
  public var notch: CGRect?
  /// How much of the bottom the Dock takes, in points.
  public var bottomInset: CGFloat
  public var displayID: CGDirectDisplayID

  public init(image: ScreenImage, notch: CGRect?, bottomInset: CGFloat = 0, displayID: CGDirectDisplayID) {
    self.image = image
    self.notch = notch
    self.bottomInset = bottomInset
    self.displayID = displayID
  }

  /// A picture file shown as if it were the main display now, for scripted tests of a capture; nil when it can't be
  /// read.
  @MainActor
  public static func mainDisplay(showing url: URL) -> Screenshot? {
    guard let screen = NSScreen.main, let image = ScreenImage(contentsOf: url, scale: screen.backingScaleFactor) else {
      return nil
    }
    return Screenshot(image: image, notch: screen.notchInPoints, bottomInset: screen.dockHeight, displayID: screen.displayNumber)
  }
}

public enum ScreenCaptureError: Error, Equatable {
  case noDisplay
}

/// Screenshots of a whole display. They need the Screen Recording permission, which also reveals other apps' window
/// titles. Its status and the request live in `PermissionsClient`: a feature checks `permissionStatuses` before it
/// captures and opens the shell's page instead of asking.
@DependencyClient
public struct ScreenCaptureClient: Sendable {
  /// The display under the pointer as it looks now, without Vortex's own windows.
  public var captureScreenUnderPointer: @Sendable () async throws -> Screenshot
}

extension ScreenCaptureClient: DependencyKey {
  public static let liveValue = ScreenCaptureClient(
    captureScreenUnderPointer: {
      let target = await MainActor.run { () -> (id: CGDirectDisplayID, scale: CGFloat, notch: CGRect?, dock: CGFloat)? in
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main
        else { return nil }
        return (screen.displayNumber, screen.backingScaleFactor, screen.notchInPoints, screen.dockHeight)
      }
      guard let target else { throw ScreenCaptureError.noDisplay }
      let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
      guard let display = content.displays.first(where: { $0.displayID == target.id }) else {
        throw ScreenCaptureError.noDisplay
      }
      let vortex = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
      let filter = SCContentFilter(display: display, excludingApplications: vortex, exceptingWindows: [])
      let configuration = SCStreamConfiguration()
      configuration.width = Int((CGFloat(display.width) * target.scale).rounded())
      configuration.height = Int((CGFloat(display.height) * target.scale).rounded())
      configuration.showsCursor = false
      configuration.captureResolution = .best
      let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
      return Screenshot(
        image: ScreenImage(cgImage: image, scale: target.scale),
        notch: target.notch,
        bottomInset: target.dock,
        displayID: target.id
      )
    }
  )

  public static let testValue = ScreenCaptureClient()
}

extension DependencyValues {
  public var screenCaptureClient: ScreenCaptureClient {
    get { self[ScreenCaptureClient.self] }
    set { self[ScreenCaptureClient.self] = newValue }
  }
}

extension NSScreen {
  /// The number Core Graphics and ScreenCaptureKit know the display by.
  var displayNumber: CGDirectDisplayID {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
  }

  /// How much of the bottom the Dock takes, in points; 0 when it is hidden or at a side.
  var dockHeight: CGFloat {
    visibleFrame.minY - frame.minY
  }

  /// The hardware notch, in points from the screen's top left corner; nil when there is none.
  var notchInPoints: CGRect? {
    guard safeAreaInsets.top > 0, let left = auxiliaryTopLeftArea?.width, let right = auxiliaryTopRightArea?.width else {
      return nil
    }
    let width = frame.width - left - right
    return width > 0 ? CGRect(x: left, y: 0, width: width, height: safeAreaInsets.top) : nil
  }
}
