import AVFoundation
import FeatureRegistry
import Foundation
import ImageIO
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

  /// Every shipped feature but the built-in ones shows itself at work on its page in the catalog: its preview's video
  /// and still are files in its own bundle, the one its title is translated from, and both can be read: the still is
  /// an image, and AVFoundation plays the video.
  @Test
  func everyShippedFeatureBringsItsCatalogMedia() async {
    for module in FeatureRegistry.all where !module.isBuiltIn {
      let id = module.id
      guard let video = module.descriptor.preview?.video, let still = module.descriptor.preview?.still else {
        Issue.record("\(id) has no video or no still in its preview")
        continue
      }
      guard case .atURL(let bundle) = module.title.bundle else {
        Issue.record("\(id)'s title isn't built from its own bundle, so its bundle is unknown here")
        continue
      }
      let bundlePath = bundle.resolvingSymlinksInPath().path + "/"
      for file in [video, still] {
        #expect(
          file.isFileURL && file.resolvingSymlinksInPath().path.hasPrefix(bundlePath),
          "\(id): \(file) is outside its bundle \(bundlePath)"
        )
        #expect(FileManager.default.isReadableFile(atPath: file.path), "\(id): \(file.path) can't be read")
      }
      let image = CGImageSourceCreateWithURL(still as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
      #expect(image != nil, "\(id): the still \(still.lastPathComponent) isn't an image")
      let asset = AVURLAsset(url: video)
      let isPlayable = (try? await asset.load(.isPlayable)) ?? false
      let pictures = (try? await asset.loadTracks(withMediaType: .video)) ?? []
      #expect(isPlayable && !pictures.isEmpty, "\(id): the video \(video.lastPathComponent) doesn't play")
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

  /// Every shipped feature's utility actions follow the rules: at most two, ids that start with the feature's id, no
  /// shortcut shared, none named like a tab's (`open-<id>`), which the shell keeps for itself. A utility, which has no
  /// tab, offers at least one action: the button it is on Home's utilities button.
  @Test
  func everyShippedFeaturesUtilityActionsFollowTheRules() {
    var shortcuts: Set<String> = []
    for module in FeatureRegistry.all {
      let actions = module.makeUtilityActions()
      #expect(UtilityAction.problems(actions, feature: module.id) == [], "\(module.id)")
      for shortcut in actions.compactMap(\.shortcut) {
        #expect(!shortcut.hasPrefix("open-") && shortcut != "openVortex", "\(module.id): \(shortcut)")
        #expect(shortcuts.insert(shortcut).inserted, "\(module.id): \(shortcut) is another feature's")
      }
      if module.kind == .utility {
        #expect(!actions.isEmpty, "\(module.id) is a utility without an action")
      }
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

  /// Keys and Screen Text wait for the user's choice; the maintainer recommends the rest, keyboard cleaning among them,
  /// as Home brought it to everyone before it became a utility.
  @Test
  func onlyHomeIsBuiltInAndKeysAndScreenTextAreNotRecommended() {
    #expect(FeatureRegistry.all.filter { $0.isBuiltIn }.map { $0.id } == ["home"])
    #expect(FeatureRegistry.all.filter { $0.isRecommended }.map { $0.id } == ["timer", "tasks", "clipboard", "shelf", "keyboard"])
  }

  /// The utilities, which have no tab, come in the catalog's order: keyboard cleaning, then Screen Text.
  @Test
  func theUtilitiesAreKeyboardCleaningAndScreenText() {
    #expect(FeatureRegistry.all.filter { $0.kind == .utility }.map { $0.id } == ["keyboard", "screentext"])
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
