import ComposableArchitecture
import SwiftUI
import VortexCore

/// Everything inside the window: the sidebar and the selected tab, or keyboard cleaning's screen over them.
struct ShellWindowView: View {
  let store: StoreOf<ShellFeature>
  @Environment(\.notchCutout) private var notchCutout

  var body: some View {
    let isCovered = store.keyboardCleaning.isLocked
    let isSidebarWaiting = store.focusedFeature != nil
    ZStack {
      HStack(spacing: 0) {
        SidebarView(store: store)
          // While a tab has the focus, as Home's editor does, the sidebar dims and waits.
          .opacity(isSidebarWaiting ? 0.35 : 1)
          .allowsHitTesting(!isSidebarWaiting)
          .disabled(isSidebarWaiting)
          .animation(.easeOut(duration: 0.2), value: isSidebarWaiting)
        TabContent(store: store)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .environment(\.notchCutout, notchCutout?.offsetBy(dx: -VortexMetrics.sidebarWidth, dy: 0))
      }
      // Under keyboard cleaning's screen the tabs stay mounted, out of sight and reach.
      .opacity(isCovered ? 0 : 1)
      .allowsHitTesting(!isCovered)
      .accessibilityHidden(isCovered)
      if let id = store.eraseConfirmation, let feature = store.features.first(where: { $0.id == id }) {
        EraseConfirmation(store: store, feature: feature)
      }
      if isCovered {
        KeyboardCleaningView(store: store.scope(state: \.keyboardCleaning, action: \.keyboardCleaning))
      }
    }
    .overlay(alignment: .bottom) {
      if !isCovered, let id = store.removedForUndo, let feature = store.features.first(where: { $0.id == id }) {
        UndoToast(store: store, feature: feature)
          .padding(.bottom, 16)
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.2), value: store.removedForUndo)
    // As large as the window chrome lays it out: the regular size, or the large one for the catalog and for a tab that
    // asks for it.
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
      case .catalog:
        CatalogView(store: store)
      case let .catalogPage(id):
        if let feature = store.features.first(where: { $0.id == id && !$0.isBuiltIn }) {
          FeaturePageView(store: store, feature: feature)
        } else {
          CatalogView(store: store)
        }
      case let .feature(id):
        // Only a running feature's tab is made; the selected tab leaves a feature that stops.
        if store.state.isAvailable(.feature(id)), let tab = FeatureViews.shared.tab(id) {
          tab
            .environment(\.windowRequest) { request in store.send(.windowRequested(id, request)) }
            // The catalog takes the window: the tab gives its focus back first, or the catalog would wait for it.
            .environment(\.showCatalog) {
              store.send(.windowRequested(id, .regular))
              store.send(.tabSelected(.catalog))
            }
            .overlay(alignment: .top) {
              // Safe mode explains itself over Home, which shows no widgets meanwhile.
              if store.isSafeMode, store.features.contains(where: { $0.id == id && $0.isBuiltIn }) {
                SafeModeBanner(store: store)
                  .padding(.top, VortexMetrics.headerHeight)
                  .padding(.leading, 10)
                  .padding(.trailing, 18)
              }
            }
        } else {
          SettingsView(store: store)
        }
      }
    }
    .environment(\.homeWidgets, homeWidgets)
    .environment(\.keyboardCleaning) { store.send(.keyboardCleaning(.startTapped)) }
  }

  /// Widgets of the running features, in sidebar order, with their feature's name and symbol: Home lays them out.
  private var homeWidgets: [HomeWidget] {
    store.runningFeatures.flatMap { feature in
      FeatureViews.shared.homeWidgets(feature.id).map { widget in
        var widget = widget
        widget.featureTitle = feature.title
        widget.featureSymbol = feature.symbol
        return widget
      }
    }
  }
}

/// Feature icons in the user's order, then the catalog and settings, kept at the bottom. Icons are reordered by
/// dragging one onto another, and scroll when there are more than fit.
private struct SidebarView: View {
  let store: StoreOf<ShellFeature>

  var body: some View {
    VStack(spacing: 2) {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 2) {
          ForEach(store.sidebarFeatures) { feature in
            SidebarButton(
              symbol: feature.symbol,
              title: Text(feature.title),
              isSelected: store.selectedTab == .feature(feature.id),
              // A permission the feature needs is off.
              warning: store.state.permissionOff(for: feature)
            ) {
              store.send(.tabSelected(.feature(feature.id)))
            }
            .reorderable(feature.id, in: store)
            .contextMenu {
              // A built-in feature has no page in the catalog and can't be removed: it has no menu.
              if !feature.isBuiltIn {
                let title = String(localized: feature.title)
                Button {
                  store.send(.tabSelected(.catalogPage(feature.id)))
                } label: {
                  Text("About \(title)", bundle: .module)
                }
                Button {
                  store.send(.featureRemoved(feature.id))
                } label: {
                  Text("Remove \(title)", bundle: .module)
                }
              }
            }
          }
        }
      }
      .scrollBounceBehavior(.basedOnSize)
      SidebarButton(
        symbol: "puzzlepiece.extension",
        title: Text("Features", bundle: .module),
        isSelected: store.selectedTab.isCatalog,
        // A feature is new, stopped after a crash, or waits in safe mode.
        hasDot: store.catalogDot
      ) {
        store.send(.tabSelected(.catalog))
      }
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
  /// like the icon.
  var warning: Permission?
  /// A plain dot on the icon: something there waits for the user.
  var hasDot = false
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
          } else if hasDot {
            Circle()
              .fill(VortexColor.accent)
              .frame(width: 6, height: 6)
              .padding(11)
              .accessibilityHidden(true)
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
