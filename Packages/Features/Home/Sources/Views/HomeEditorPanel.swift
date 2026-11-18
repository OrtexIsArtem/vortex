import ComposableArchitecture
import SwiftUI
import VortexCore

/// The editor's panel on the right: Done, then the features with widgets (those on Home, then the others) with a search
/// and the way to the catalog, or one feature's widgets.
struct HomeEditorPanel: View {
  let store: StoreOf<HomeFeature>
  let byID: [String: HomeWidget]
  let showCatalog: (@MainActor () -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Spacer(minLength: 0)
        Button {
          store.send(.doneTapped)
        } label: {
          Text("Done", bundle: .module)
        }
        .buttonStyle(.primaryCapsule)
      }
      .frame(height: 34)

      switch store.panel {
      case .features:
        FeatureList(store: store, showCatalog: showCatalog)
      case let .feature(feature):
        FeatureWidgets(store: store, feature: feature, byID: byID)
      }
    }
    .padding(.top, 10)
    .padding(.horizontal, 12)
    .padding(.bottom, 10)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(VortexColor.panel)
    .overlay(alignment: .leading) {
      Rectangle().fill(VortexColor.line).frame(width: 1)
    }
  }
}

/// The search, the features with widgets in two sections, and the way to the catalog.
private struct FeatureList: View {
  let store: StoreOf<HomeFeature>
  let showCatalog: (@MainActor () -> Void)?
  @FocusState private var isSearchFocused: Bool

  var body: some View {
    let sections = store.panelSections
    PanelSearchField(
      query: Binding(get: { store.search }, set: { store.send(.searchChanged($0)) }),
      isFocused: $isSearchFocused
    )
    .padding(.top, 10)

    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if !sections.onHome.isEmpty {
          SectionTitle(text: Text("On Home", bundle: .module)).padding(.top, 14)
          ForEach(sections.onHome, id: \.self) { FeatureRow(store: store, feature: $0) }
        }
        if !sections.more.isEmpty {
          SectionTitle(text: Text("More", bundle: .module)).padding(.top, 12)
          ForEach(sections.more, id: \.self) { FeatureRow(store: store, feature: $0) }
        }
        if sections.onHome.isEmpty, sections.more.isEmpty, !store.search.isEmpty {
          Text("Nothing found", bundle: .module)
            .font(.system(size: 12))
            .foregroundStyle(VortexColor.tertiaryText)
            .padding(.top, 14)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollIndicators(.never)

    if let showCatalog {
      Button {
        // The editor ends first: the catalog takes the window.
        store.send(.doneTapped)
        showCatalog()
      } label: {
        HStack(spacing: 3) {
          Text("More widgets in Features", bundle: .module)
          Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .semibold))
        }
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(.top, 6)
    }
  }
}

private struct SectionTitle: View {
  let text: Text

  var body: some View {
    text
      .font(.system(size: 11.5))
      .foregroundStyle(VortexColor.tertiaryText)
      .accessibilityAddTraits(.isHeader)
  }
}

/// A feature in the panel: its symbol and name, and how many of its widgets there are and how many show on Home. It
/// opens the feature's widgets.
private struct FeatureRow: View {
  let store: StoreOf<HomeFeature>
  let feature: FeatureID

  var body: some View {
    let own = store.widgets.filter { $0.feature == feature }
    let onHome = own.filter { store.shownWidgets.contains($0.id) }.count
    Button {
      store.send(.featureTapped(feature), animation: .snappy(duration: 0.25))
    } label: {
      HStack(spacing: 10) {
        Image(systemName: own.first?.featureSymbol ?? "square")
          .font(.system(size: 13))
          .foregroundStyle(VortexColor.primaryText)
          .frame(width: 28, height: 28)
          .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(VortexColor.raised))
        VStack(alignment: .leading, spacing: 1) {
          Text(verbatim: own.first?.featureName ?? "")
            .font(.system(size: 12.5))
            .foregroundStyle(VortexColor.primaryText)
          subtitle(widgets: own.count, onHome: onHome, isNotchRow: own.count == 1 && own[0].id == store.notchRowWidget)
            .font(.system(size: 11))
            .foregroundStyle(VortexColor.tertiaryText)
        }
        .lineLimit(1)
        // The names take what the row leaves, without a spacer's extra gap: "1 віджет · на головній" fits.
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(VortexColor.tertiaryText)
      }
      .frame(height: VortexMetrics.hitTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.top, 4)
  }

  /// "2 widgets · 1 on Home", "1 widget · on Home", "1 widget", or "In the notch row".
  private func subtitle(widgets: Int, onHome: Int, isNotchRow: Bool) -> Text {
    if isNotchRow { return Text("In the notch row", bundle: .module) }
    let count = Text("\(widgets) widgets", bundle: .module)
    guard onHome > 0 else { return count }
    let where_ = widgets == 1 ? Text("on Home", bundle: .module) : Text("\(onHome) on Home", bundle: .module)
    return count + Text(verbatim: " · ") + where_
  }
}

/// One feature's widgets: back to the list, the feature's name, and a card for each widget.
private struct FeatureWidgets: View {
  let store: StoreOf<HomeFeature>
  let feature: FeatureID
  let byID: [String: HomeWidget]

  var body: some View {
    let own = store.widgets.filter { $0.feature == feature }
    Button {
      store.send(.backTapped, animation: .snappy(duration: 0.25))
    } label: {
      HStack(spacing: 3) {
        Image(systemName: "chevron.left")
          .font(.system(size: 9, weight: .semibold))
        Text("Widgets", bundle: .module)
      }
      .font(.system(size: 12.5))
      .foregroundStyle(VortexColor.secondaryText)
      .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.top, 6)

    Text(verbatim: own.first?.featureName ?? "")
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(VortexColor.primaryText)
      .padding(.top, 2)

    ScrollView {
      VStack(spacing: 12) {
        ForEach(own, id: \.id) { info in
          PanelWidget(store: store, info: info, widget: byID[info.id])
        }
      }
      .padding(.vertical, 12)
      // Room for the cards' rings, which a scroll view would clip.
      .padding(.horizontal, 1)
    }
    .scrollIndicators(.never)
  }
}

/// A widget in the panel: its preview, its name and whether it is on Home, its sizes, and Add. Under the pointer its
/// copy shows on Home where it would go.
private struct PanelWidget: View {
  let store: StoreOf<HomeFeature>
  let info: HomeWidgetInfo
  let widget: HomeWidget?
  @State private var isHovered = false

  var body: some View {
    let sizes: [HomeWidgetSize] = if case let .grid(sizes) = info.place { sizes } else { [] }
    let placement = store.visible.first { $0.widget == info.id }
    let isOnHome = store.shownWidgets.contains(info.id)
    let size = placement?.size ?? store.chosenSizes[info.id] ?? sizes.first
    let hasNoRoom = if case .noRoom = store.state.place(for: info.id) { true } else { false }
    let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
    VStack(alignment: .leading, spacing: 8) {
      if let widget {
        WidgetThumbnail(widget: widget, size: size)
      }
      HStack {
        Text(verbatim: info.name)
          .font(.system(size: 12.5))
          .foregroundStyle(VortexColor.primaryText)
        Spacer(minLength: 4)
        if !isOnHome, !hasNoRoom {
          Button {
            store.send(.addTapped(info.id), animation: .snappy(duration: 0.25))
          } label: {
            Text("Add", bundle: .module)
          }
          .buttonStyle(PrimaryCapsuleButtonStyle(height: 24, fontSize: 11))
        } else {
          (isOnHome ? Text("On Home", bundle: .module) : Text("No room", bundle: .module))
            .font(.system(size: 11))
            .foregroundStyle(VortexColor.tertiaryText)
        }
      }
      .lineLimit(1)
      .frame(minHeight: 24)
      if sizes.isEmpty {
        Text("In the notch row", bundle: .module)
          .font(.system(size: 11))
          .foregroundStyle(VortexColor.tertiaryText)
      } else {
        HStack(spacing: 6) {
          ForEach(sizes, id: \.self) { option in
            // On Home a size applies in place, so one that doesn't fit there is dimmed.
            let fitsInPlace = placement.map { placement in
              HomeLayout(notchRow: nil, placed: store.visible)
                .fits(option, column: placement.column, row: placement.row, ignoring: [info.id])
            }
            SizeChip(size: option, isChosen: option == size, isEnabled: fitsInPlace ?? true) {
              store.send(.sizeTapped(info.id, option), animation: .snappy(duration: 0.25))
            }
          }
        }
      }
      if hasNoRoom, !sizes.isEmpty {
        Text("Remove a widget or choose a smaller size.", bundle: .module)
          .font(.system(size: 11))
          .foregroundStyle(VortexColor.tertiaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(10)
    .background(shape.fill(VortexColor.primaryText.opacity(isHovered ? 0.05 : 0.02)))
    .overlay(shape.strokeBorder(VortexColor.primaryText.opacity(isHovered ? 0.16 : 0.07), lineWidth: 1))
    .contentShape(shape)
    .onHover { isInside in
      isHovered = isInside
      store.send(.hovered(isInside ? info.id : nil), animation: .easeOut(duration: 0.15))
    }
  }
}

/// A widget at its real size, scaled down to the panel's width and kept short.
private struct WidgetThumbnail: View {
  let widget: HomeWidget
  let size: HomeWidgetSize?
  /// The widest and tallest a preview gets in the panel.
  private static let box = CGSize(width: 154, height: 96)

  var body: some View {
    let real = size?.points ?? CGSize(width: HomeGrid.frame(column: 0, row: 0, size: .full).width, height: VortexMetrics.headerHeight)
    let scale = min(Self.box.width / real.width, Self.box.height / real.height)
    Group {
      if let size {
        WidgetFace(widget: widget, size: size)
      } else {
        // The notch row's widget, as wide as Home.
        widget.view
          .frame(width: real.width, height: real.height)
          .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(VortexColor.dock))
      }
    }
    .scaleEffect(scale, anchor: .topLeading)
    .frame(width: real.width * scale, height: real.height * scale, alignment: .topLeading)
    // The card's edge, which its own shade barely shows on the panel.
    .overlay(
      RoundedRectangle(cornerRadius: (size == nil ? 14 : 18) * scale, style: .continuous)
        .strokeBorder(VortexColor.primaryText.opacity(0.1), lineWidth: 1)
    )
    .frame(maxWidth: .infinity)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// A size in a widget's switcher: "2×1"; the chosen one filled, one that doesn't fit where the widget is dimmed.
private struct SizeChip: View {
  let size: HomeWidgetSize
  let isChosen: Bool
  let isEnabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(verbatim: size.label)
        .font(.system(size: 11, weight: .semibold).monospacedDigit())
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(isChosen ? VortexColor.accent : VortexColor.raised))
        .foregroundStyle(isChosen ? VortexColor.onAccent : VortexColor.primaryText)
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    // The chosen size stays enabled, or macOS would dim it like one that doesn't fit; choosing it again changes nothing.
    .disabled(!isEnabled)
    .opacity(isEnabled || isChosen ? 1 : 0.35)
    .accessibilityAddTraits(isChosen ? .isSelected : [])
  }
}

/// The panel's search: a magnifier, "Search widgets" and a button that empties it. Esc empties it too; in an empty
/// field Esc goes on to the window, which closes.
private struct PanelSearchField: View {
  @Binding var query: String
  var isFocused: FocusState<Bool>.Binding

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11))
        .foregroundStyle(VortexColor.tertiaryText)
      TextField(text: $query) {
        Text("Search widgets", bundle: .module)
      }
      .textFieldStyle(.plain)
      .font(.system(size: 12.5))
      .focused(isFocused)
      .onKeyPress(.escape) {
        guard !query.isEmpty else { return .ignored }
        query = ""
        return .handled
      }
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 11))
            .foregroundStyle(VortexColor.tertiaryText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Clear search", bundle: .module))
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 30)
    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(VortexColor.raised))
  }
}
