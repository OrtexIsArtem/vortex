import ComposableArchitecture
import Foundation
import VortexCore

/// What the onboarding remembers across launches, in DataFolder/onboarding.json, never in UserDefaults: QA
/// runs share one defaults domain. A missing file means a fresh install, or one from before this stage: the onboarding
/// shows once.
struct OnboardingProgress: Codable, Equatable, Sendable {
  /// The page the onboarding shows, by `OnboardingPage.id`.
  var page = OnboardingPage.welcome.id
  /// A page opened from one of Done's rows goes back to Done on Next or Skip.
  var returnToDone = false
  /// Permissions whose check waits for a relaunch: the pasteboard once its pane was opened from its page.
  var pendingChecks: Set<Permission> = []
  /// A single page to show once after the relaunch it started.
  var pendingSingle: Permission?
  /// The final button on Done was pressed.
  var completed = false
  /// Vortex relaunched during the onboarding; it never offers a second restart.
  var restarted = false
  /// The user's "Open at login" choice was applied when they left Basics; from then on the row shows the real state.
  var loginItemApplied = false

  init() {}

  /// Each field on its own: a missing, unknown or broken value takes its default and the rest of the file stays, so a
  /// file from another build, or one edited by hand, never drops `completed`. Unknown permissions are left out.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    page = value(.page, OnboardingPage.welcome.id)
    returnToDone = value(.returnToDone, false)
    pendingChecks = Set(value(.pendingChecks, [String]()).compactMap(Permission.init(rawValue:)))
    pendingSingle = (try? container.decodeIfPresent(String.self, forKey: .pendingSingle)).flatMap(Permission.init(rawValue:))
    completed = value(.completed, false)
    restarted = value(.restarted, false)
    loginItemApplied = value(.loginItemApplied, false)
  }
}

/// Reads and writes DataFolder/onboarding.json. Writes are synchronous, so a forced quit right after a page change
/// still resumes there.
@DependencyClient
struct OnboardingProgressClient: Sendable {
  var load: @Sendable () -> OnboardingProgress = { OnboardingProgress() }
  var save: @Sendable (_ progress: OnboardingProgress) -> Void
}

extension OnboardingProgressClient: DependencyKey {
  static let liveValue = live(at: DataFolder.url.appending(path: "onboarding.json"))

  /// The file at `url`; one that can't be read at all is a fresh onboarding.
  static func live(at url: URL) -> OnboardingProgressClient {
    OnboardingProgressClient(
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
  }

  static let testValue = OnboardingProgressClient()
}

extension DependencyValues {
  var onboardingProgress: OnboardingProgressClient {
    get { self[OnboardingProgressClient.self] }
    set { self[OnboardingProgressClient.self] = newValue }
  }
}
