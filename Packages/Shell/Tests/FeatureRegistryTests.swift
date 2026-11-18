import FeatureRegistry
import Foundation
import Testing
import VortexCore

@testable import VortexShell

// Home's first layout is its own (`HomeLayout`), read here to check the shipped features' widgets together; a build
// without Home, as any feature can be removed, leaves the check out.
#if canImport(FeatureHome)
  @testable import FeatureHome
#endif

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

  #if canImport(FeatureHome)
    /// Home's first layout of the shipped features, in the default sidebar order, is Home as it was before its grid:
    /// the timer in the row next to the notch, Clipboard's history and the shelf side by side, 2×2 each. A new user
    /// starts with it, and so does the update from that Home.
    @Test
    func theShippedFeaturesFirstLayoutIsHomeAsItWasBeforeItsGrid() {
      let widgets = FeatureRegistry.all.flatMap { module in
        module.makeHomeWidgets().map { widget in
          HomeWidgetInfo(
            id: widget.id, feature: widget.feature, place: widget.place, name: widget.id, featureName: module.id,
            featureSymbol: module.symbol
          )
        }
      }
      let layout = HomeLayout.initial(widgets)
      #expect(layout.notchRow == "timer.timer")
      #expect(
        layout.placed == [
          Placement(widget: "clipboard.history", size: .large, column: 0, row: 0),
          Placement(widget: "shelf.files", size: .large, column: 2, row: 0),
        ]
      )
    }
  #endif

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
