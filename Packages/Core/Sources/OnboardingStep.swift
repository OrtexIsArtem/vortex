import ComposableArchitecture
import SwiftUI

/// A feature's own onboarding page, shown after the permission pages. The shell asks for it with
/// `FeatureModule.makeOnboardingStep()` and hosts the view; the onboarding offers Skip until the feature marks the step
/// done in `@Shared(.onboardingStepsDone)`.
public struct OnboardingStep {
  public var id: FeatureID
  public var title: LocalizedStringResource
  public var view: AnyView

  @MainActor
  public init(id: FeatureID, title: LocalizedStringResource, view: some View) {
    self.id = id
    self.title = title
    self.view = AnyView(view)
  }
}

extension SharedReaderKey where Self == InMemoryKey<Set<FeatureID>>.Default {
  /// Feature steps that are done: a feature inserts its own id, and the onboarding then shows Next instead of Skip.
  public static var onboardingStepsDone: Self {
    Self[.inMemory("onboardingStepsDone"), default: []]
  }
}
