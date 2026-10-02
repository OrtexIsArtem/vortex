import ComposableArchitecture
import Testing

@testable import FeatureTemplate

@MainActor
struct TemplateFeatureTests {
  @Test
  func incrementButtonTapped() async {
    let store = TestStore(initialState: TemplateFeature.State()) {
      TemplateFeature()
    }

    await store.send(.incrementButtonTapped) {
      $0.count = 1
    }
  }
}
