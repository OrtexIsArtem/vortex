import Foundation
import VortexCore

/// What Erase Data deletes from the data folder for a feature: its settings file `<id>.json` and its folder
/// (`FeatureModule.dataFolder`), each only when its name is one plain name (letters, digits, spaces, `-` and `_`) and
/// the settings file isn't one of the shell's own. So no value in a feature's description can reach outside its files.
enum EraseTargets {
  /// The shell's own files in the data folder, `<name>.json`.
  static let shellFiles: Set<String> = ["settings", "onboarding", "permissions", "launch"]

  static func paths(id: FeatureID, dataFolder: String?, in root: URL) -> [URL] {
    var paths: [URL] = []
    if isPlain(id), !shellFiles.contains(id.lowercased()) {
      paths.append(root.appending(path: "\(id).json"))
    }
    if let dataFolder, isPlain(dataFolder) {
      paths.append(root.appending(path: dataFolder, directoryHint: .isDirectory))
    }
    return paths
  }

  /// One name, never a path: it starts with a letter or digit and holds only letters, digits, spaces, `-` and `_`.
  static func isPlain(_ name: String) -> Bool {
    guard let first = name.unicodeScalars.first, CharacterSet.alphanumerics.contains(first) else { return false }
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
    return name.unicodeScalars.allSatisfy(allowed.contains)
  }
}

extension FeatureDescriptor {
  /// Whether the feature says it keeps anything: what (`keeps`), a folder or a note for erasing it. One that says none,
  /// as Screen Text, never offers Erase Data, not even while its Undo shows.
  var keepsData: Bool {
    keeps != nil || dataFolder != nil || eraseNote != nil
  }
}
