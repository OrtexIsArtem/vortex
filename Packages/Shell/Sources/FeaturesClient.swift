import ComposableArchitecture
import FeatureRegistry
import Foundation
import VortexCore
import VortexPlatform

/// Lets ShellFeature reach the feature modules without knowing their types.
@DependencyClient
struct FeaturesClient: Sendable {
  /// Starts or stops the background work of a feature, see `FeatureModule.setEnabled`.
  var setEnabled: @Sendable (_ id: FeatureID, _ isEnabled: Bool) async -> Void
  /// Hands files to a feature that takes them, see `FeatureModule.receiveFiles`.
  var receiveFiles: @Sendable (_ id: FeatureID, _ urls: [URL]) async -> Void
  /// What the feature keeps on disk, in bytes: its folder (`FeatureModule.dataFolder`) and its settings file
  /// `<id>.json`; 0 when it keeps only rows in the database, nil when it keeps nothing at all.
  var dataSize: @Sendable (_ id: FeatureID) async -> Int64? = { _ in nil }
  /// Erase Data, at launch before anything starts: the feature's tables and migrations, its settings file and folder,
  /// its tab shortcut, then its own `eraseData()` for what only it knows, given at most 10 s.
  var eraseData: @Sendable (_ id: FeatureID) async -> Void
  /// The widgets of these running features, in their order, without their views: what Home lays out.
  var homeWidgets: @Sendable (_ ids: [FeatureID]) async -> [HomeWidgetInfo] = { _ in [] }
  /// The utility actions of these running features, in their order, as plain data: what the shell runs and listens for.
  var utilityActions: @Sendable (_ ids: [FeatureID]) async -> [UtilityActionInfo] = { _ in [] }
  /// Runs a running feature's utility action, see `UtilityAction.perform`.
  var performUtilityAction: @Sendable (_ feature: FeatureID, _ id: String) async -> Void
}

extension FeaturesClient: DependencyKey {
  /// Each call into a feature is marked in the launch record, so a crash inside it stops that feature next launch.
  static let liveValue = FeaturesClient(
    setEnabled: { id, isEnabled in
      @Dependency(\.launchGuard) var launchGuard
      await MainActor.run {
        launchGuard.around(id) { FeatureRegistry.module(for: id)?.setEnabled(isEnabled) }
      }
    },
    receiveFiles: { id, urls in
      @Dependency(\.launchGuard) var launchGuard
      await MainActor.run {
        launchGuard.around(id) { FeatureRegistry.module(for: id)?.receiveFiles(urls) }
      }
    },
    dataSize: { id in
      @Dependency(\.fileClient) var files
      @Dependency(\.database) var database
      // Plain data: no feature's code runs to tell its folder.
      let folder = await MainActor.run { FeatureRegistry.module(for: id)?.dataFolder }
      var bytes: Int64 = 0
      var keepsAnything = false
      if let folder {
        let url = DataFolder.url.appending(path: folder, directoryHint: .isDirectory)
        if await files.info(url) != nil {
          keepsAnything = true
          bytes += await files.folderSize(url)
        }
      }
      if let settings = await files.info(DataFolder.url.appending(path: "\(id).json")) {
        keepsAnything = true
        bytes += settings.size ?? 0
      }
      // Rows only, such as a clipboard history of text: still something to erase.
      if !keepsAnything, (try? await database.keepsFeatureData(id)) == true {
        keepsAnything = true
      }
      return keepsAnything ? bytes : nil
    },
    eraseData: { id in
      @Dependency(\.database) var database
      @Dependency(\.fileClient) var files
      @Dependency(\.hotkeyClient) var hotkeys
      try? await database.eraseFeature(id)
      let folder = await MainActor.run { FeatureRegistry.module(for: id)?.dataFolder }
      for path in EraseTargets.paths(id: id, dataFolder: folder, in: DataFolder.url) {
        await files.remove(path)
      }
      await hotkeys.reset(.open(id))
      await eraseHook(of: id, within: .seconds(10))
    },
    homeWidgets: { ids in
      await MainActor.run {
        ids.flatMap { id -> [HomeWidgetInfo] in
          guard let module = FeatureRegistry.module(for: id) else { return [] }
          // Made once, as the views of a running feature are (FeatureViews).
          return FeatureViews.shared.homeWidgets(id).map { widget in
            HomeWidgetInfo(
              id: widget.id,
              feature: widget.feature,
              place: widget.place,
              name: String(localized: widget.title),
              featureName: String(localized: module.title),
              featureSymbol: module.symbol
            )
          }
        }
      }
    },
    utilityActions: { ids in
      await MainActor.run {
        // Made once, as the views of a running feature are (FeatureViews).
        ids.flatMap { FeatureViews.shared.utilityActions($0).map(\.info) }
      }
    },
    performUtilityAction: { feature, id in
      @Dependency(\.launchGuard) var launchGuard
      await MainActor.run {
        launchGuard.around(feature) { FeatureViews.shared.utilityActions(feature).first { $0.id == id }?.perform() }
      }
    }
  )

  /// Runs the feature's own erase hook, but waits for it no longer than `limit`: a hook that hangs mustn't hold the
  /// launch. The hook goes on meanwhile, and the launch record names no feature for it.
  private static func eraseHook(of id: FeatureID, within limit: Duration) async {
    let isDone = LockIsolated(false)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let finish: @Sendable () -> Void = {
        let isFirst = isDone.withValue { done in
          defer { done = true }
          return !done
        }
        if isFirst { continuation.resume() }
      }
      Task { @MainActor in
        await FeatureRegistry.module(for: id)?.eraseData()
        finish()
      }
      Task {
        try? await Task.sleep(for: limit)
        finish()
      }
    }
  }

  /// Unimplemented, but for Home's widgets and the utility actions: a test without features that offer any reads none.
  static let testValue: FeaturesClient = {
    var client = FeaturesClient()
    client.homeWidgets = { _ in [] }
    client.utilityActions = { _ in [] }
    return client
  }()
}

extension DependencyValues {
  var featuresClient: FeaturesClient {
    get { self[FeaturesClient.self] }
    set { self[FeaturesClient.self] = newValue }
  }
}
