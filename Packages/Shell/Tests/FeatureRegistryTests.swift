import FeatureRegistry
import Foundation
import Testing
import VortexCore

/// The features the app ships describe themselves for the catalog.
@MainActor
struct FeatureRegistryTests {
  @Test
  func everyShippedFeatureDescribesItself() {
    for module in FeatureRegistry.all {
      let d = module.descriptor
      #expect(!String(localized: d.summary).isEmpty, "\(d.id) has no summary")
      #expect(!String(localized: d.details).isEmpty, "\(d.id) has no details")
      #expect(!d.author.isEmpty, "\(d.id) has no author")
    }
  }

  @Test
  func onlyHomeIsBuiltInAndKeysIsTheOneNotRecommended() {
    #expect(FeatureRegistry.all.filter { $0.isBuiltIn }.map { $0.id } == ["home"])
    #expect(FeatureRegistry.all.filter { $0.isRecommended }.map { $0.id } == ["timer", "tasks", "clipboard", "shelf"])
  }
}
