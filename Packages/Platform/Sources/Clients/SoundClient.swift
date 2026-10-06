import AppKit
import ComposableArchitecture

/// The system's alert sounds, such as the one the timer plays when time is up.
@DependencyClient
public struct SoundClient: Sendable {
  /// Names of the system sounds, sorted: "Basso", "Blow", … "Tink".
  public var names: @Sendable () async -> [String] = { [] }
  /// Plays a system sound by name, stopping the one still playing; an unknown name plays nothing.
  public var play: @Sendable (_ name: String) async -> Void
}

extension SoundClient: DependencyKey {
  public static let liveValue = SoundClient(
    names: { SystemSounds.names() },
    play: { name in await SystemSounds.play(name) }
  )

  public static let testValue = SoundClient()
}

extension DependencyValues {
  public var soundClient: SoundClient {
    get { self[SoundClient.self] }
    set { self[SoundClient.self] = newValue }
  }
}

enum SystemSounds {
  static let folder = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)

  /// Sound files in the folder, by name without the extension.
  static func names(in folder: URL = folder) -> [String] {
    let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    return files
      .filter { !$0.lastPathComponent.hasPrefix(".") }
      .map { $0.deletingPathExtension().lastPathComponent }
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  /// The sound playing, kept so the next one can stop it.
  @MainActor private static var playing: NSSound?

  @MainActor
  static func play(_ name: String) {
    playing?.stop()
    playing = NSSound(named: NSSound.Name(name))
    playing?.play()
  }
}
