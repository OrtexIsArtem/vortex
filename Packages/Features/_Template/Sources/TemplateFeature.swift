import ComposableArchitecture
import SwiftUI
import VortexCore

/// Entry point the app shell reads. Register it in Features/Registry.
public enum TemplateModule: FeatureModule {
  public static let id = "template"
  public static let title: LocalizedStringResource = "Template"
  public static let symbol = "square.dashed"
}

@Reducer
public struct TemplateFeature {
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

public struct TemplateView: View {
  let store: StoreOf<TemplateFeature>

  public init(store: StoreOf<TemplateFeature>) {
    self.store = store
  }

  public var body: some View {
    VStack(spacing: 12) {
      Text(store.count, format: .number)
        .font(.largeTitle.monospacedDigit())
      Button("Increment") {
        store.send(.incrementButtonTapped)
      }
    }
    .padding()
  }
}
