import ComposableArchitecture
import Foundation
import VortexCore

/// What the onboarding remembers across launches (S21, S71), in DataFolder/onboarding.json, never in UserDefaults: QA
/// runs share one defaults domain. A missing file means a fresh install, or one from before this stage: the onboarding
/// shows once (S7).
struct OnboardingProgress: Codable, Equatable, Sendable {
  /// The page the onboarding shows, by `OnboardingPage.id`.
  var page = OnboardingPage.welcome.id
  /// A page opened from one of Done's rows goes back to Done on Next or Skip (S18, S77).
  var returnToDone = false
  /// Permissions whose check waits for a relaunch: the pasteboard once its pane was opened from its page (S16, S68).
  var pendingChecks: Set<Permission> = []
  /// A single page to show once after the relaunch it started (S50).
  var pendingSingle: Permission?
  /// The final button on Done was pressed (S8).
  var completed = false
  /// Vortex relaunched during the onboarding; it never offers a second restart (S68).
  var restarted = false
  /// The user's "Open at login" choice was applied when they left Basics (S74); from then on the row shows the real state.
  var loginItemApplied = false

  init() {}

  init(from decoder: Decoder) throws {
    // Every field has a default, so a file written by an older or newer build still reads.
    let container = try decoder.container(keyedBy: CodingKeys.self)
    page = try container.decodeIfPresent(String.self, forKey: .page) ?? OnboardingPage.welcome.id
    returnToDone = try container.decodeIfPresent(Bool.self, forKey: .returnToDone) ?? false
    pendingChecks = try container.decodeIfPresent(Set<Permission>.self, forKey: .pendingChecks) ?? []
    pendingSingle = try container.decodeIfPresent(Permission.self, forKey: .pendingSingle)
    completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false
    restarted = try container.decodeIfPresent(Bool.self, forKey: .restarted) ?? false
    loginItemApplied = try container.decodeIfPresent(Bool.self, forKey: .loginItemApplied) ?? false
  }
}

/// Reads and writes DataFolder/onboarding.json. Writes are synchronous, so a forced quit right after a page change
/// still resumes there (S21, S71).
@DependencyClient
struct OnboardingProgressClient: Sendable {
  var load: @Sendable () -> OnboardingProgress = { OnboardingProgress() }
  var save: @Sendable (_ progress: OnboardingProgress) -> Void
}

extension OnboardingProgressClient: DependencyKey {
  static let liveValue: OnboardingProgressClient = {
    let url = DataFolder.url.appending(path: "onboarding.json")
    return OnboardingProgressClient(
      load: {
        guard let data = try? Data(contentsOf: url) else { return OnboardingProgress() }
        return (try? JSONDecoder().decode(OnboardingProgress.self, from: data)) ?? OnboardingProgress()
      },
      save: { progress in
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(progress).write(to: url, options: .atomic)
      }
    )
  }()

  static let testValue = OnboardingProgressClient()
}

extension DependencyValues {
  var onboardingProgress: OnboardingProgressClient {
    get { self[OnboardingProgressClient.self] }
    set { self[OnboardingProgressClient.self] = newValue }
  }
}
