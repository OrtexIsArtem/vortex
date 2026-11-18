import ComposableArchitecture
import SwiftUI
import VortexCore

/// The editor's panel on the right: Done, a search, the features with widgets (those on Home, then the others) and the
/// way to the catalog for more.
struct HomeEditorPanel: View {
  let store: StoreOf<HomeFeature>
  let showCatalog: (@MainActor () -> Void)?
  @FocusState private var isSearchFocused: Bool

  var body: some View {
    let sections = store.panelSections
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

private struct SectionTitle: View {
  let text: Text

  var body: some View {
    text
      .font(.system(size: 11.5))
      .foregroundStyle(VortexColor.tertiaryText)
      .accessibilityAddTraits(.isHeader)
  }
}

/// A feature in the panel: its symbol and name, and how many of its widgets there are and how many show on Home.
private struct FeatureRow: View {
  let store: StoreOf<HomeFeature>
  let feature: FeatureID

  var body: some View {
    let own = store.widgets.filter { $0.feature == feature }
    let onHome = own.filter { store.shownWidgets.contains($0.id) }.count
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
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(VortexColor.tertiaryText)
    }
    .frame(height: VortexMetrics.hitTarget)
    .padding(.top, 4)
    .accessibilityElement(children: .combine)
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
