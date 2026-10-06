import ComposableArchitecture
import Foundation
import VortexCore

/// What the Tasks feature keeps between launches besides the tasks. Stored as JSON; unreadable keys fall back to their
/// defaults.
public struct TasksSettings: Codable, Equatable, Sendable {
  /// The system's own prompt for Screen Recording was shown once already. It never shows again, so after it a capture
  /// without access opens System Settings instead.
  public var askedForScreenRecording = false

  public init() {}

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    askedForScreenRecording = (try? container.decodeIfPresent(Bool.self, forKey: .askedForScreenRecording)) ?? false
  }
}

extension SharedKey where Self == FileStorageKey<TasksSettings>.Default {
  /// DataFolder/tasks.json.
  static var tasksSettings: Self {
    Self[.fileStorage(DataFolder.url.appending(path: "tasks.json")), default: TasksSettings()]
  }
}
