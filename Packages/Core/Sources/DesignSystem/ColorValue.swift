import AppKit
import SwiftUI

/// A color that can be stored, compared and sent between features and the shell: sRGB components from 0 to 1.
public struct ColorValue: Codable, Hashable, Sendable {
  public var red: Double
  public var green: Double
  public var blue: Double

  public init(red: Double, green: Double, blue: Double) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  public init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }

  /// The color a SwiftUI color shows on screen, such as one picked in the color panel.
  public init(_ color: Color) {
    let resolved = NSColor(color).usingColorSpace(.sRGB) ?? .white
    self.init(red: Double(resolved.redComponent), green: Double(resolved.greenComponent), blue: Double(resolved.blueComponent))
  }

  public static let white = ColorValue(red: 1, green: 1, blue: 1)

  public var color: Color {
    Color(.sRGB, red: red, green: green, blue: blue)
  }
}
