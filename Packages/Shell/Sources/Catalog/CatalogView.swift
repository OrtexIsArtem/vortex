import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The catalog: every feature Vortex ships but the built-in ones, those added and those you can add, in the large
/// window. A card opens the feature's page.
struct CatalogView: View {
  let store: StoreOf<ShellFeature>
  private let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Features", bundle: .module)
        .font(.system(size: 13, weight: .semibold))
        .frame(height: VortexMetrics.headerHeight)
        .padding(.leading, 10)

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text("Everything is built into Vortex and works offline. Add what you need, remove what you don't.", bundle: .module)
            .font(.system(size: 12.5))
            .foregroundStyle(VortexColor.tertiaryText)

          if store.isSafeMode {
            SafeModeBanner(store: store, showsCatalogButton: false)
          }

          let added = store.catalogAdded
          if !added.isEmpty {
            section(Text("Added", bundle: .module), count: added.count, features: added, isAdded: true)
          }
          let available = store.catalogAvailable
          if available.isEmpty {
            Text("Everything is added", bundle: .module)
              .font(.system(size: 12))
              .foregroundStyle(VortexColor.tertiaryText)
          } else {
            section(Text("Can add", bundle: .module), count: available.count, features: available, isAdded: false)
          }
        }
        .padding(.leading, 10)
        .padding(.trailing, 18)
        .padding(.bottom, 18)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func section(_ title: Text, count: Int, features: [FeatureDescriptor], isAdded: Bool) -> some View {
    let rows = features.map { ($0, badges(for: $0, isAdded: isAdded)) }
    // Cards in a section share one height: taller when one of them has badges.
    let height: CGFloat = rows.contains { !$0.1.isEmpty } ? 104 : 84
    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        title.foregroundStyle(VortexColor.secondaryText)
        Text(verbatim: "\(count)").monospacedDigit().foregroundStyle(VortexColor.tertiaryText)
      }
      .font(.system(size: 12))
      LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
        ForEach(rows, id: \.0.id) { feature, badges in
          CatalogCard(
            feature: feature,
            badges: badges,
            warning: isAdded ? store.state.permissionOff(for: feature) : nil,
            start: startAction(for: feature, isAdded: isAdded)
          ) {
            store.send(.tabSelected(.catalogPage(feature.id)))
          }
          .frame(height: height)
        }
      }
    }
  }

  private func badges(for feature: FeatureDescriptor, isAdded: Bool) -> [CatalogBadge] {
    var badges: [CatalogBadge] = []
    if !isAdded, feature.isRecommended { badges.append(.recommended) }
    if store.visitNew.contains(feature.id) { badges.append(.new) }
    if feature.isBeta { badges.append(.beta) }
    if feature.suspension != nil {
      badges.append(.paused)
    } else if isAdded, store.settings.stoppedFeatures.contains(feature.id) {
      badges.append(.stopped)
    }
    return badges
  }

  /// In safe mode an added feature that waits starts from its card.
  private func startAction(for feature: FeatureDescriptor, isAdded: Bool) -> (() -> Void)? {
    guard isAdded, store.isSafeMode, feature.suspension == nil, !store.settings.stoppedFeatures.contains(feature.id),
          !store.runningFeatures.contains(where: { $0.id == feature.id })
    else { return nil }
    return { store.send(.startFeatureTapped(feature.id)) }
  }
}
