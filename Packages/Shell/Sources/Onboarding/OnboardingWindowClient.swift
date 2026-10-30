import ComposableArchitecture

/// How the onboarding window shows.
enum OnboardingWindowMode: String, Equatable, Sendable {
  /// The full window, about 560×620 pt.
  case window
  /// The small guide panel next to System Settings.
  case panel
  /// The panel, stepped aside while another app is in front.
  case panelHidden
}

/// The onboarding's window, as OnboardingFeature sees it. Only the shell uses it.
@DependencyClient
struct OnboardingWindowClient: Sendable {
  /// Shows the window as `mode`; `activate` brings Vortex to the front with it, which a hover never does.
  var present: @Sendable (_ mode: OnboardingWindowMode, _ activate: Bool) async -> Void
  /// Hides it; `restoreFront` gives the front back to the app that had it before a single page opened.
  var hide: @Sendable (_ restoreFront: Bool) async -> Void
}

extension OnboardingWindowClient: DependencyKey {
  static let liveValue = OnboardingWindowClient(
    present: { mode, activate in await OnboardingWindowController.shared.present(mode, activate: activate) },
    hide: { restoreFront in await OnboardingWindowController.shared.hide(restoreFront: restoreFront) }
  )

  static let testValue = OnboardingWindowClient()
}

extension DependencyValues {
  var onboardingWindow: OnboardingWindowClient {
    get { self[OnboardingWindowClient.self] }
    set { self[OnboardingWindowClient.self] = newValue }
  }
}
