import FeatureRegistry
import Foundation
import Testing
import VortexCore

@testable import VortexShell

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

  /// Every shipped feature's Home widgets follow Home's rules (design 6.2): at most two, ids that start with the
  /// feature's id, one to three sizes each. A contributor's feature is checked here even without a test of its own.
  @Test
  func everyShippedFeaturesWidgetsFollowHomesRules() {
    for module in FeatureRegistry.all {
      #expect(HomeWidget.problems(module.makeHomeWidgets(), feature: module.id) == [], "\(module.id)")
    }
  }

  @Test
  func onlyHomeIsBuiltInAndKeysIsTheOneNotRecommended() {
    #expect(FeatureRegistry.all.filter { $0.isBuiltIn }.map { $0.id } == ["home"])
    #expect(FeatureRegistry.all.filter { $0.isRecommended }.map { $0.id } == ["timer", "tasks", "clipboard", "shelf"])
  }

  /// Erase Data can reach every shipped feature's settings file and folder, and nothing of another feature's: each
  /// folder is a plain name, none is shared (folders are compared as macOS does, regardless of case), and no id names
  /// one of the shell's own files.
  @Test
  func everyShippedFeatureErasesOnlyItsOwnFiles() {
    let root = URL(fileURLWithPath: "/data", isDirectory: true)
    var folders: Set<String> = []
    for module in FeatureRegistry.all {
      let paths = EraseTargets.paths(id: module.id, dataFolder: module.dataFolder, in: root)
      #expect(paths.count == (module.dataFolder == nil ? 1 : 2), "\(module.id)")
      if let folder = module.dataFolder {
        #expect(folders.insert(folder.lowercased()).inserted, "\(folder) is shared")
      }
    }
  }

}
