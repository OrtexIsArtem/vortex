import ComposableArchitecture
import SwiftUI
import VortexCore

/// The onboarding's Features page, right after Welcome: the features to start with, the recommended ones checked. The
/// list scrolls; the footer stays, with how many are chosen and what Vortex asks for next.
struct FeaturesPage: View {
  let store: StoreOf<OnboardingFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      FittingPage {
        VStack(alignment: .leading, spacing: 0) {
          Text("Choose your features", bundle: .module)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(VortexColor.primaryText)
            .padding(.top, 52)
          Text("Recommended ones are already on. You can add or remove any of them later in Features.", bundle: .module)
            .font(.system(size: 13))
            .foregroundStyle(VortexColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
          VStack(spacing: 0) {
            ForEach(store.choosable) { feature in
              FeatureChoiceRow(feature: feature, isChosen: store.chosen.contains(feature.id)) {
                store.send(.featureToggled(feature.id))
              }
            }
          }
          .padding(.top, 18)
        }
      }
      Hairline()
      footer
        .frame(height: 72)
    }
    .padding(.horizontal, 40)
  }

  private var footer: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text("\(store.chosen.count) of \(store.choosable.count) features chosen", bundle: .module)
          .foregroundStyle(VortexColor.secondaryText)
        Text("Next, Vortex asks for: \(asks)", bundle: .module)
          .foregroundStyle(VortexColor.tertiaryText)
      }
      .font(.system(size: 11.5))
      .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        store.send(.nextTapped)
      } label: {
        Text("Next", bundle: .module)
      }
      .buttonStyle(PrimaryCapsuleButtonStyle(height: 36, fontSize: 13))
      .keyboardShortcut(.defaultAction)
      .disabled(!store.buttons.nextEnabled)
    }
  }

  /// The permissions the next pages ask for, from what the chosen features and keyboard cleaning need.
  private var asks: String {
    store.catalog.entries
      .filter { store.statuses[$0.permission] != .notNeeded }
      .map { String(localized: $0.permission.title) }
      .formatted(.list(type: .and, width: .narrow))
  }
}

/// A feature to check or uncheck: its box, symbol, name and line, and the permissions it needs.
private struct FeatureChoiceRow: View {
  let feature: FeatureDescriptor
  let isChosen: Bool
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      HStack(spacing: 14) {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(isChosen ? VortexColor.accent : .clear)
          .strokeBorder(isChosen ? .clear : VortexColor.track, lineWidth: 1.5)
          .frame(width: 20, height: 20)
          .overlay {
            if isChosen {
              Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(VortexColor.onAccent)
            }
          }
        Image(systemName: feature.symbol)
          .font(.system(size: 16))
          .foregroundStyle(VortexColor.primaryText)
          .frame(width: 34, height: 34)
          .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(VortexColor.raised))
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 7) {
            Text(feature.title)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(VortexColor.primaryText)
            if feature.isRecommended {
              Text("Recommended", bundle: .module)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VortexColor.secondaryText)
                .padding(.horizontal, 6)
                .frame(height: 17)
                .overlay(Capsule().strokeBorder(VortexColor.track))
            }
          }
          Text(feature.summary)
            .font(.system(size: 12))
            .foregroundStyle(VortexColor.secondaryText)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if !feature.permissionNeeds.isEmpty {
          Text(feature.permissionNeeds.map { String(localized: $0.permission.title) }.formatted(.list(type: .and, width: .narrow)))
            .font(.system(size: 11))
            .foregroundStyle(VortexColor.tertiaryText)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 132, alignment: .trailing)
        }
      }
      .frame(height: 66)
      .contentShape(Rectangle())
      .overlay(alignment: .bottom) { Hairline() }
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(isChosen ? [.isSelected] : [])
  }
}
