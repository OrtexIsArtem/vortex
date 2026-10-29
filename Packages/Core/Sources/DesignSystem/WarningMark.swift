import SwiftUI

/// The yellow warning of a permission that is off (S22): a triangle next to a control or in a settings row, or a dot on
/// a feature's icon in the sidebar. Given the permission, it says "Notifications are off" as a tooltip and to VoiceOver
/// (`Permission.offLabel`); without one, VoiceOver reads "Needs a permission".
public struct WarningMark: View {
  public enum Style: Sendable {
    /// `exclamationmark.triangle.fill`, `size` points tall.
    case triangle
    /// A dot `size` points wide, ringed in the window's background so it stands apart from the icon under it.
    case dot
  }

  private let permission: Permission?
  private let style: Style
  private let size: CGFloat

  public init(_ permission: Permission? = nil, style: Style = .triangle, size: CGFloat? = nil) {
    self.permission = permission
    self.style = style
    self.size = size ?? (style == .triangle ? 12 : 7)
  }

  public var body: some View {
    let mark = Group {
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
    if let permission {
      mark
        .accessibilityLabel(Text(permission.offLabel))
        .help(Text(permission.offLabel))
    } else {
      mark.accessibilityLabel(Text("Needs a permission", bundle: .module))
    }
  }
}
