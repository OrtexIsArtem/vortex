# Shell
The app shell: the notch window, the menu bar icon, the sidebar, the catalog, the shell settings, the onboarding and keyboard cleaning.

| File | What it covers |
| --- | --- |
| behavior.md | when the window opens and closes, which tab it shows, permission statuses and blocking |
| catalog.md | which features run, the catalog and a feature's page, Erase Data, window sizes, crashes and safe mode |
| keyboard-cleaning.md | the keyboard lock, its lock screen, and the drawn keyboard each press washes |
| onboarding.md | the first-run onboarding, the single permission page, blocked mode and the guide panel |
| settings.md | shell settings and their defaults |
| data.md | where the settings and the onboarding's progress live, what Vortex asked macOS for |
| contracts.md | what the shell gives the app and takes from features, Core and Platform |

Logic, tested: ShellFeature.swift, KeyboardCleaning/, Permissions/, Onboarding/OnboardingFeature.swift, LaunchGuard/ (launch record, crash verdict), Window/ScreenGeometry.swift and WindowSizeRules.swift, MoveToApplications/MoveToApplications.swift (the move to /Applications at launch, App/docs/README.md).
AppKit, SwiftUI: ShellController.swift (start-up, menu), FeatureViews.swift (features' views, made once), FeaturesClient.swift, Window/ (notch, ears, menu bar icon, the main menu that never shows), Views/, Catalog/, Settings/, Onboarding/ (window, panel, pages, illustration, animation), MoveToApplications/MoveAlertClient.swift (its alerts), KeyboardCleaning/KeyboardCleaningView.swift, LaunchGuard/CrashSignals.swift. Debug only: QA/, Onboarding/OnboardingQA.swift.
