# Shell
The app shell: the notch window, the menu bar icon, the sidebar, the catalog, Home's utilities dock, the covers utilities show over the window, the shell settings and the onboarding.

| File | What it covers |
| --- | --- |
| behavior.md | when the window opens and closes, which tab it shows, the utilities dock, a utility's cover, permission statuses and blocking |
| catalog.md | which features and utilities run, the catalog and a feature's page, Erase Data, window sizes, crashes and safe mode |
| onboarding.md | the first-run onboarding, the single permission page, blocked mode and the guide panel |
| settings.md | shell settings and their defaults |
| data.md | where the settings and the onboarding's progress live, what Vortex asked macOS for |
| contracts.md | what the shell gives the app and takes from features, Core and Platform |

Logic, tested: ShellFeature.swift, Permissions/, Onboarding/OnboardingFeature.swift, LaunchGuard/ (launch record, crash verdict), Settings/ShellSettings.swift (with the one-time feature migrations), Window/ScreenGeometry.swift and WindowSizeRules.swift, MoveToApplications/MoveToApplications.swift (the move to /Applications at launch, App/docs/README.md).
AppKit, SwiftUI: ShellController.swift (start-up, menu), FeatureViews.swift (features' views, made once), FeaturesClient.swift, Window/ (notch, ears, menu bar icon, the main menu that never shows, WindowCoversClient), Views/, Catalog/, Settings/, Onboarding/ (window, panel, pages, illustration, animation), MoveToApplications/MoveAlertClient.swift (its alerts), LaunchGuard/CrashSignals.swift. Debug only: QA/, Onboarding/OnboardingQA.swift.
