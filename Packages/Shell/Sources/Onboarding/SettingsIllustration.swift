import AppKit
import SwiftUI
import VortexCore
import VortexPlatform

/// A drawn mock of the System Settings pane for a permission, never a screenshot (S36): a sidebar hint, the
/// breadcrumb, two faded rows with no real names, and Vortex's row with its icon and a switch. Every ~3 s a pointer
/// moves to the switch and turns it on; with Reduce Motion the switch is on, with an arrow pointing at it.
struct SettingsIllustration: View {
  let permission: Permission
  var compact = false
  @Environment(\.reduceMotion) private var reduceMotion
  @State private var pointerAtSwitch = false
  @State private var isOn = false

  var body: some View {
    let scale: CGFloat = compact ? 0.72 : 1
    HStack(spacing: 0) {
      sidebar
        .frame(width: 92 * scale)
      Rectangle().fill(VortexColor.line).frame(width: 1)
      VStack(alignment: .leading, spacing: 10 * scale) {
        Text(IllustrationText.breadcrumb(permission))
          .font(.system(size: 11 * scale, weight: .semibold))
          .foregroundStyle(VortexColor.primaryText)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
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
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(VortexColor.line, lineWidth: 1))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(IllustrationText.breadcrumb(permission)))
    .task(id: reduceMotion) { await play() }
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
      Text(IllustrationText.rowTitle(permission))
        .font(.system(size: 11 * scale, weight: .medium))
        .foregroundStyle(VortexColor.primaryText)
      Spacer()
      ZStack {
        Capsule()
          .fill(isOn ? Color.accentColor : VortexColor.track)
          .frame(width: 26 * scale, height: 15 * scale)
          .overlay(alignment: isOn ? .trailing : .leading) {
            Circle().fill(Color.white).frame(width: 12 * scale, height: 12 * scale).padding(1.5)
          }
        pointer(scale)
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 38 * scale)
  }

  @ViewBuilder
  private func pointer(_ scale: CGFloat) -> some View {
    if reduceMotion {
      Image(systemName: "arrow.left")
        .font(.system(size: 13 * scale, weight: .bold))
        .foregroundStyle(VortexColor.primaryText)
        .offset(x: 30 * scale)
    } else {
      Image(systemName: "cursorarrow")
        .font(.system(size: 15 * scale))
        .foregroundStyle(VortexColor.primaryText)
        .shadow(color: .black.opacity(0.25), radius: 1)
        .offset(x: pointerAtSwitch ? 4 * scale : -60 * scale, y: pointerAtSwitch ? 6 * scale : 34 * scale)
        .opacity(pointerAtSwitch || isOn ? 1 : 0.0)
    }
  }

  /// Every ~3 s: the pointer moves to the switch, the switch turns on, then it starts over.
  private func play() async {
    guard !reduceMotion else {
      isOn = true
      return
    }
    while !Task.isCancelled {
      isOn = false
      pointerAtSwitch = false
      try? await Task.sleep(for: .milliseconds(500))
      withAnimation(.easeInOut(duration: 0.8)) { pointerAtSwitch = true }
      try? await Task.sleep(for: .milliseconds(900))
      withAnimation(.snappy(duration: 0.2)) { isOn = true }
      try? await Task.sleep(for: .milliseconds(1_600))
      withAnimation(.easeOut(duration: 0.3)) { pointerAtSwitch = false }
      try? await Task.sleep(for: .milliseconds(300))
    }
  }
}

/// The illustration's words, as System Settings on macOS 26 names its panes (S36, S75).
enum IllustrationText {
  static func breadcrumb(_ permission: Permission) -> LocalizedStringResource {
    switch permission {
    case .notifications:
      LocalizedStringResource("Notifications › Vortex", bundle: .atURL(Bundle.module.bundleURL))
    case .accessibility:
      LocalizedStringResource("Privacy & Security › Accessibility", bundle: .atURL(Bundle.module.bundleURL))
    case .screenRecording:
      LocalizedStringResource("Privacy & Security › Screen & System Audio Recording", bundle: .atURL(Bundle.module.bundleURL))
    case .pasteboard:
      LocalizedStringResource("Privacy & Security › Paste from Other Apps", bundle: .atURL(Bundle.module.bundleURL))
    }
  }

  static func rowTitle(_ permission: Permission) -> LocalizedStringResource {
    permission == .notifications
      ? LocalizedStringResource("Allow notifications", bundle: .atURL(Bundle.module.bundleURL))
      : LocalizedStringResource(stringLiteral: "Vortex")
  }
}
