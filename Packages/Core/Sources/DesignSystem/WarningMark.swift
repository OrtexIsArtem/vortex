import SwiftUI

/// The yellow warning of a permission that is off (S22): a triangle next to a control or in a settings row, or a dot on
/// a feature's icon in the sidebar. VoiceOver reads it as "Needs a permission".
public struct WarningMark: View {
  public enum Style: Sendable {
    /// `exclamationmark.triangle.fill`, `size` points tall.
    case triangle
    /// A dot `size` points wide, ringed in the window's background so it stands apart from the icon under it.
    case dot
  }

  private let style: Style
  private let size: CGFloat

  public init(style: Style = .triangle, size: CGFloat? = nil) {
    self.style = style
    self.size = size ?? (style == .triangle ? 12 : 7)
  }

  public var body: some View {
    Group {
      switch style {
      case .triangle:
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: size, weight: .semibold))
          .foregroundStyle(VortexColor.warning)
      case .dot:
        Circle()
          .fill(VortexColor.warning)
          .frame(width: size, height: size)
          .overlay(Circle().stroke(VortexColor.windowBackground, lineWidth: 1.5))
      }
    }
    .accessibilityElement()
    .accessibilityLabel(Text("Needs a permission", bundle: .module))
  }
}
