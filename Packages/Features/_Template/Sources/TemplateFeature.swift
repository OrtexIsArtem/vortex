import ComposableArchitecture
import SwiftUI
import VortexCore

/// Entry point the app shell reads. Register it in Features/Registry.
@MainActor
public enum TemplateModule: FeatureModule {
  public static let id: FeatureID = "template"
  public static let title = LocalizedStringResource("Template", bundle: .atURL(Bundle.module.bundleURL))
  public static let symbol = "square.dashed"
  public static let summary = LocalizedStringResource("A starting point for a new feature", bundle: .atURL(Bundle.module.bundleURL))
  public static let details = LocalizedStringResource("Copy this folder to start a feature of your own.", bundle: .atURL(Bundle.module.bundleURL))
  public static let author = "@OrtexIsArtem"

  /// One store for the life of the app, so the tab keeps its state between openings.
  private static let store = Store(initialState: TemplateFeature.State()) {
    TemplateFeature()
  }

  public static func makeTab() -> AnyView {
    AnyView(TemplateView(store: store))
  }

  /// One widget, Small or Medium, which the user puts on Home from the editor or the feature's page. Its id starts with
  /// the feature's; `TemplateFeatureTests` checks the rules, and the `#Preview`s below show each size on Home's grid.
  public static func makeHomeWidgets() -> [HomeWidget] {
    [
      HomeWidget(
        id: "template.count",
        feature: id,
        title: LocalizedStringResource("Count", bundle: .atURL(Bundle.module.bundleURL)),
        place: .grid([.small, .medium]),
        view: AnyView(TemplateHomeWidget(store: store))
      ),
    ]
  }
}

@Reducer
public struct TemplateFeature: Sendable {
  @ObservableState
  public struct State: Equatable {
    public var count = 0

    public init() {}
  }

  public enum Action: Equatable {
    case incrementButtonTapped
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .incrementButtonTapped:
        state.count += 1
        return .none
      }
    }
  }
}

/// The template's widget on Home: the count, and at Medium the button that raises it. Its size comes from the
/// environment (`homeWidgetSize`).
struct TemplateHomeWidget: View {
  let store: StoreOf<TemplateFeature>
  @Environment(\.homeWidgetSize) private var size

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Template", bundle: .module)
        .font(.system(size: 12))
        .foregroundStyle(VortexColor.secondaryText)
      Text(store.count, format: .number)
        .font(.system(size: 15, weight: .medium).monospacedDigit())
      if size == .medium {
        Spacer(minLength: 0)
        Button {
          store.send(.incrementButtonTapped)
        } label: {
          Text("Increment", bundle: .module)
        }
        .buttonStyle(.quietCapsule)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

#Preview("Widget, Small") {
  HomeWidgetPreview(TemplateModule.makeHomeWidgets()[0], size: .small)
}

#Preview("Widget, Medium") {
  HomeWidgetPreview(TemplateModule.makeHomeWidgets()[0], size: .medium)
}

public struct TemplateView: View {
  let store: StoreOf<TemplateFeature>

  public init(store: StoreOf<TemplateFeature>) {
    self.store = store
  }

  public var body: some View {
    VStack(spacing: 12) {
      Text(store.count, format: .number)
        .font(.largeTitle.monospacedDigit())
      Button {
        store.send(.incrementButtonTapped)
      } label: {
        Text("Increment", bundle: .module)
      }
    }
    .padding()
  }
}
