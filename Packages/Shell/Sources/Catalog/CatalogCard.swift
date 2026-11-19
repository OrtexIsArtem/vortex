import SwiftUI
import VortexCore
import VortexPlatform

/// A feature in the catalog: its symbol, name and one line, with its badges. A click opens its page.
struct CatalogCard: View {
  let feature: FeatureDescriptor
  let badges: [CatalogBadge]
  /// A permission the added feature needs is off.
  var warning: Permission?
  /// In safe mode, an added feature that waits gets a Start button.
  var start: (() -> Void)?
  let open: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: open) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: feature.symbol)
          .font(.system(size: 16))
          .foregroundStyle(VortexColor.primaryText)
          .frame(width: 36, height: 36)
          .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(VortexColor.raised))
          .overlay(alignment: .topTrailing) {
            if let warning {
              WarningMark(warning, style: .dot).offset(x: 3, y: -3)
            }
          }
        VStack(alignment: .leading, spacing: 3) {
          Text(feature.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(VortexColor.primaryText)
          Text(feature.summary)
            .font(.system(size: 11.5))
            .foregroundStyle(VortexColor.secondaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
          if !badges.isEmpty {
            HStack(spacing: 5) {
              ForEach(badges, id: \.self) { CatalogBadgeView(badge: $0) }
            }
            .padding(.top, 5)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Room for the Start button, which sits over the card's right edge.
        .padding(.trailing, start == nil ? 0 : 72)
      }
      .padding(14)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(VortexColor.card)
          .strokeBorder(isHovered ? VortexColor.track : VortexColor.cardEdge)
      )
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
    .overlay(alignment: .trailing) {
      if let start {
        Button(action: start) {
          Text("Start", bundle: .module)
        }
        .buttonStyle(.quietCapsule)
        .fixedSize()
        .padding(.trailing, 14)
      }
    }
    .onHover { isHovered = $0 }
    .accessibilityElement(children: .combine)
  }
}

/// A utility in the catalog's Utilities section, one compact row: its symbol, name and one line, with its badges, a
/// button onto its page; at the end the switch that adds or removes it, by Add and Remove's rules.
struct UtilityRow: View {
  let feature: FeatureDescriptor
  let badges: [CatalogBadge]
  /// A permission the added utility needs is off.
  var warning: Permission?
  let isAdded: Bool
  /// False while the maintainer pauses it: the switch shows and doesn't move.
  let switchable: Bool
  let switched: @MainActor (Bool) -> Void
  let open: () -> Void
  @State private var isHovered = false

  var body: some View {
    HStack(spacing: 8) {
      Button(action: open) {
        HStack(spacing: 12) {
          Image(systemName: feature.symbol)
            .font(.system(size: 14))
            .foregroundStyle(VortexColor.primaryText)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(VortexColor.raised))
            .overlay(alignment: .topTrailing) {
              if let warning {
                WarningMark(warning, style: .dot).offset(x: 3, y: -3)
              }
            }
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
              Text(feature.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VortexColor.primaryText)
              ForEach(badges, id: \.self) { CatalogBadgeView(badge: $0) }
            }
            Text(feature.summary)
              .font(.system(size: 11.5))
              .foregroundStyle(VortexColor.secondaryText)
              .lineLimit(1)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 14)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .onHover { isHovered = $0 }
      .accessibilityElement(children: .combine)
      Toggle(isOn: Binding(get: { isAdded }, set: { switched($0) })) {
        Text(feature.title)
      }
      .toggleStyle(.vortex)
      .disabled(!switchable)
      .padding(.trailing, 8)
    }
    .background(VortexColor.primaryText.opacity(isHovered ? 0.03 : 0))
  }
}

/// The marks a catalog card can carry.
enum CatalogBadge: Hashable {
  case recommended
  case new
  case beta
  case stopped
  case paused

  var title: Text {
    switch self {
    case .recommended: Text("Recommended", bundle: .module)
    case .new: Text("New", bundle: .module)
    case .beta: Text("Beta", bundle: .module)
    case .stopped: Text("Stopped", bundle: .module)
    case .paused: Text("Paused", bundle: .module)
    }
  }
}

private struct CatalogBadgeView: View {
  let badge: CatalogBadge

  var body: some View {
    badge.title
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(badge == .new ? VortexColor.onAccent : badge == .beta ? VortexColor.tertiaryText : VortexColor.secondaryText)
      .padding(.horizontal, 7)
      .frame(height: 18)
      .background(
        Capsule()
          .fill(badge == .new ? VortexColor.accent : .clear)
          .strokeBorder(badge == .new ? .clear : VortexColor.track)
      )
  }
}
