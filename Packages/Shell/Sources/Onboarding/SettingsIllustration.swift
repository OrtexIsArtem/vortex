import AppKit
import SwiftUI
import VortexCore
import VortexPlatform

/// A drawn mock of the System Settings pane for a permission, never a screenshot: a sidebar hint, the
/// breadcrumb, two faded rows with no real names, and Vortex's row with its icon and a switch. Every ~3 s a pointer
/// moves to the switch and turns it on, played by Core Animation (`SwitchFlipAnimation`), so the page costs no CPU
/// while it shows; with Reduce Motion the switch is on, with an arrow pointing at it.
struct SettingsIllustration: View {
  let permission: Permission
  /// System Settings' own names on this Mac (`IllustrationText`).
  let names: SystemSettingsNames
  var compact = false
  @Environment(\.reduceMotion) private var reduceMotion

  var body: some View {
    let scale: CGFloat = compact ? 0.72 : 1
    HStack(spacing: 0) {
      sidebar
        .frame(width: 92 * scale)
      Rectangle().fill(VortexColor.line).frame(width: 1)
      VStack(alignment: .leading, spacing: 10 * scale) {
        Text(verbatim: IllustrationText.breadcrumb(permission, names))
          .font(.system(size: 11 * scale, weight: .semibold))
          .foregroundStyle(VortexColor.primaryText)
          // Wraps rather than cutting a long pane name short (uk).
          .fixedSize(horizontal: false, vertical: true)
        VStack(spacing: 0) {
          fadedRow(scale)
          Hairline()
          vortexRow(scale)
          Hairline()
          fadedRow(scale)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(VortexColor.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(VortexColor.cardEdge, lineWidth: 1))
        Spacer(minLength: 0)
      }
      .padding(12 * scale)
    }
    .background(VortexColor.raised.opacity(0.5))
    .overlayPreferenceValue(IllustrationSwitchAnchor.self) { anchor in
      if let anchor, !reduceMotion {
        GeometryReader { proxy in
          SwitchFlipAnimation(switchFrame: proxy[anchor], scale: scale)
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(VortexColor.line, lineWidth: 1))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: IllustrationText.breadcrumb(permission, names)))
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 4) {
        ForEach([Color.red, .yellow, .green], id: \.self) { color in
          Circle().fill(color.opacity(0.55)).frame(width: 7, height: 7)
        }
      }
      .padding(.bottom, 6)
      ForEach(0 ..< 5, id: \.self) { index in
        RoundedRectangle(cornerRadius: 3)
          .fill(index == 2 ? VortexColor.track : VortexColor.line)
          .frame(width: CGFloat(44 + (index * 13) % 26), height: 7)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func fadedRow(_ scale: CGFloat) -> some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 5).fill(VortexColor.track).frame(width: 18 * scale, height: 18 * scale)
      RoundedRectangle(cornerRadius: 3).fill(VortexColor.track).frame(width: 70 * scale, height: 7 * scale)
      Spacer()
      Capsule().fill(VortexColor.track).frame(width: 26 * scale, height: 15 * scale)
    }
    .opacity(0.55)
    .padding(.horizontal, 10)
    .frame(height: 34 * scale)
  }

  private func vortexRow(_ scale: CGFloat) -> some View {
    HStack(spacing: 8) {
      Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
        .resizable()
        .frame(width: 18 * scale, height: 18 * scale)
      Text(verbatim: IllustrationText.rowTitle(permission, names))
        .font(.system(size: 11 * scale, weight: .medium))
        .foregroundStyle(VortexColor.primaryText)
      Spacer()
      // Off, as the animation over it starts; on, with an arrow pointing at it, under Reduce Motion.
      Capsule()
        .fill(reduceMotion ? Color.accentColor : VortexColor.track)
        .frame(width: 26 * scale, height: 15 * scale)
        .overlay(alignment: reduceMotion ? .trailing : .leading) {
          Circle().fill(Color.white).frame(width: 12 * scale, height: 12 * scale).padding(1.5)
        }
        .anchorPreference(key: IllustrationSwitchAnchor.self, value: .bounds) { $0 }
        .overlay(alignment: .trailing) {
          if reduceMotion {
            Image(systemName: "arrow.left")
              .font(.system(size: 13 * scale, weight: .bold))
              .foregroundStyle(VortexColor.primaryText)
              .offset(x: 20 * scale)
          }
        }
    }
    .padding(.horizontal, 10)
    .frame(height: 38 * scale)
  }
}

/// The illustration's words, as System Settings names its panes on this Mac: read from System Settings itself, in the
/// system's language and for this macOS version, so they match what the user sees there even when Vortex speaks
/// another language. A breadcrumb with a name macOS doesn't give falls back whole to Vortex's own words, macOS 26's
/// names in Vortex's language, so it never mixes two languages.
enum IllustrationText {
  static func breadcrumb(_ permission: Permission, _ names: SystemSettingsNames) -> String {
    switch permission {
    case .notifications:
      names.notifications.map { "\($0) › Vortex" }
        ?? String(localized: "Notifications › Vortex", bundle: .module)
    case .accessibility:
      privacy(names, names.accessibility)
        ?? String(localized: "Privacy & Security › Accessibility", bundle: .module)
    case .screenRecording:
      privacy(names, names.screenRecording)
        ?? String(localized: "Privacy & Security › Screen & System Audio Recording", bundle: .module)
    case .pasteboard:
      privacy(names, names.pasteFromOtherApps)
        ?? String(localized: "Privacy & Security › Paste from Other Apps", bundle: .module)
    }
  }

  /// Vortex's row: the switch's label on its Notifications page, else the app's name.
  static func rowTitle(_ permission: Permission, _ names: SystemSettingsNames) -> String {
    guard permission == .notifications else { return "Vortex" }
    // From the same files as the breadcrumb, so both are in one language.
    guard names.notifications != nil, let allow = names.allowNotifications else {
      return String(localized: "Allow notifications", bundle: .module)
    }
    return allow
  }

  private static func privacy(_ names: SystemSettingsNames, _ pane: String?) -> String? {
    guard let privacy = names.privacyAndSecurity, let pane else { return nil }
    return "\(privacy) › \(pane)"
  }
}
