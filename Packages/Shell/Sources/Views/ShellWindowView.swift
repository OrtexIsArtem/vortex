import ComposableArchitecture
import FeatureRegistry
import SwiftUI
import VortexCore

/// Everything inside the window: the sidebar and the selected tab, or keyboard cleaning's screen over them.
struct ShellWindowView: View {
  let store: StoreOf<ShellFeature>
  @Environment(\.notchCutout) private var notchCutout

  var body: some View {
    let isCovered = store.keyboardCleaning.isLocked
    ZStack {
      HStack(spacing: 0) {
        SidebarView(store: store)
        TabContent(store: store)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .environment(\.notchCutout, notchCutout?.offsetBy(dx: -VortexMetrics.sidebarWidth, dy: 0))
      }
      // Under keyboard cleaning's screen the tabs stay mounted, out of sight and reach.
      .opacity(isCovered ? 0 : 1)
      .allowsHitTesting(!isCovered)
      .accessibilityHidden(isCovered)
      if isCovered {
        KeyboardCleaningView(store: store.scope(state: \.keyboardCleaning, action: \.keyboardCleaning))
      }
    }
    .frame(width: VortexMetrics.windowSize.width, height: VortexMetrics.windowSize.height)
    .font(.system(size: 13))
    .foregroundStyle(VortexColor.primaryText)
  }
}

private struct TabContent: View {
  let store: StoreOf<ShellFeature>

  var body: some View {
    Group {
      switch store.selectedTab {
      case .settings:
        SettingsView(store: store)
      case let .feature(id):
        if let module = FeatureRegistry.module(for: id) {
          module.makeTab()
        } else {
          SettingsView(store: store)
        }
      }
    }
    .environment(\.homeWidgets, homeWidgets)
    .environment(\.keyboardCleaning) { store.send(.keyboardCleaning(.startTapped)) }
  }

  /// Widgets of the enabled features, in sidebar order: Home lays them out.
  private var homeWidgets: [HomeWidget] {
    store.sidebarFeatures.compactMap { FeatureRegistry.module(for: $0.id)?.makeHomeWidget() }
  }
}

/// Feature icons in the user's order, settings at the bottom. Icons are reordered by dragging one onto another.
private struct SidebarView: View {
  let store: StoreOf<ShellFeature>

  var body: some View {
    VStack(spacing: 2) {
      ForEach(store.sidebarFeatures) { feature in
        SidebarButton(
          symbol: feature.symbol,
          title: Text(feature.title),
          isSelected: store.selectedTab == .feature(feature.id),
          // A permission the feature needs is off (S22.2, S39).
          warning: feature.permissionNeeds.firstOff(in: store.permissionStatuses)
        ) {
          store.send(.tabSelected(.feature(feature.id)))
        }
        .reorderable(feature.id, in: store)
      }
      Spacer(minLength: 0)
      SidebarButton(
        symbol: "gearshape",
        title: Text("Settings", bundle: .module),
        isSelected: store.selectedTab == .settings
      ) {
        store.send(.tabSelected(.settings))
      }
    }
    .padding(.top, VortexMetrics.headerHeight)
    .padding(.bottom, 16)
    .frame(width: VortexMetrics.sidebarWidth)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text("Sections", bundle: .module))
  }
}

private struct SidebarButton: View {
  let symbol: String
  let title: Text
  let isSelected: Bool
  /// A yellow dot on the icon: decoration with its own tooltip ("Notifications are off"); a click on it opens the tab
  /// like the icon (S39).
  var warning: Permission?
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 16))
        .frame(width: VortexMetrics.hitTarget, height: VortexMetrics.hitTarget)
        .foregroundStyle(foreground)
        .background(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(isSelected ? VortexColor.raised : .clear)
        )
        .overlay(alignment: .topTrailing) {
          if let warning {
            WarningMark(warning, style: .dot).padding(9)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help(title)
    .accessibilityLabel(title)
    .accessibilityValue(warning.map { Text($0.offLabel) } ?? Text(verbatim: ""))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private var foreground: Color {
    if isSelected { return VortexColor.primaryText }
    return isHovered ? VortexColor.secondaryText : VortexColor.tertiaryText
  }
}

extension View {
  /// Lets a feature's row or icon be dragged onto another one to reorder features.
  /// Only feature ids of this app count as a drop; anything else is refused.
  func reorderable(_ id: FeatureID, in store: StoreOf<ShellFeature>) -> some View {
    draggable(id)
      .dropDestination(for: String.self) { items, _ in
        guard let dragged = items.first, store.features.contains(where: { $0.id == dragged }) else { return false }
        store.send(.featureDropped(dragged, onto: id))
        return true
      }
  }
}
