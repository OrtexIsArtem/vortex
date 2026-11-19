# Contracts

## Provides
- `ShellController` — created by App at launch: `start()`, `receiveFiles(_:)` for files opened with Vortex, `prepareToTerminate()` when the app is asked to quit (a quit System Settings asked for reopens Vortex: `QuitRequest`, `SystemClient.reopenAfterQuit`), and `saveSettings()` when it quits.
- `ShellController.moveToApplicationsIfAccepted()`, which App calls before creating the shell: in a release build it may offer the move to /Applications (App/docs/README.md); true when Vortex moved and quits, so App starts nothing.
- To feature tabs: `notchCutout` and `isWindowOpen` in the SwiftUI environment.
- Puts the Home widgets of running features, in sidebar order, into the environment of the tab content (`homeWidgets`).
- Tells Home the same widgets as `HomeWidgetInfo` through `@Shared(.runningHomeWidgets)`: at launch once every feature has started, even none (safe mode), then whenever the running features or their order change; written in the reducer, in order; only the shell writes it.
- Puts `windowRequest` and `showCatalog` into a feature tab's environment: a request for a window size and the focus, which closing the window forgets; `showCatalog` gives the focus back, then shows the catalog.
- "Add to Home" on a feature's page adds its id to `@Shared(.homeAddRequests)`, once; the page reads `@SharedReader(.featuresOnHome)` for "On Home", and `@Shared(.noRoomOnHome)` for "No room on Home", which the shell empties whenever the window's tab changes.
- Puts `keyboardCleaning` there too: the action behind Home's keyboard button.
- `@Shared(.permissionStatuses)`: what macOS says, from `PermissionsClient.updates()` at launch on, and re-read each time the window opens (`refresh()`). Only the shell writes it.
- `@Shared(.appBlocked)`: true while a permission that is required and needed reads `notGranted`; false before the first read. `notNeeded` and `grantedAfterRestart` count as on. Only the shell writes it.
- Needed (`PermissionCatalog`): the `permissionNeeds` of added features but paused ones, in sidebar order, plus Accessibility for keyboard cleaning while Home (id `home`, which has the button) is added, with the reason "Locks the keyboard while you clean it."
- Required: `OnboardingConfig.requiredPermissions`, empty now, copied into the state, where QA mode may change it. It counts only for needed permissions.
- Takes the requests of `PermissionPage` from launch on and shows each as the single page in the onboarding window.
- Hosts `FeatureModule.makeOnboardingStep()` of running features after the permission pages, and on the feature's catalog page while not done; Skip shows until the feature puts its id in `@Shared(.onboardingStepsDone)`.

## Owns
- The notch window, the ears around the notch and the menu bar icon (Window/). Nothing outside the shell opens or closes the window.
- The onboarding window and its guide panel (Onboarding/).

## Uses
- FeatureRegistry: every `FeatureModule` — its descriptor (`permissionNeeds` and the catalog's fields), read for every feature; `makeTab()`, `makeSettings()`, `makeHomeWidgets()` and `makeOnboardingStep()` through `FeatureViews` (each made once, only for a running feature), `receiveFiles(_:)` and `setEnabled(_:)`, each call marked in the launch record; `eraseData()` at launch for a feature being erased.
- VortexCore: `FeatureModule`, `@Shared(.notchIndicators)` (a feature that doesn't run has its indicator hidden), `Permission`, `PermissionPage`, design system, `WindowSize`, `AppTheme`, `AppLanguage`, `eraseFeature(_:)` of the database, `DataFolder`.
- VortexPlatform: `HotkeyClient` (`shortcut` names "Open Vortex" in Done's hint; `reset` forgets an erased feature's tab shortcut), `LaunchAtLoginClient` (`isSetUp` starts Basics' switch from the real state), `SystemSettingsNamesClient` (the pane names of the onboarding's drawing, read at launch), `SystemClient` (`relaunchFrom` after the move to /Applications), `AppInstallClient` (where this copy runs, the app in /Applications, the move), `KeyboardLockClient` (`lock`, `unlock`; `presses`, the keys it holds back as places on the drawn keyboard, until `unlock`; `layout`, the board to draw, read at each lock), `PermissionsClient` (`requested`, read at launch for an install that kept no grants), `ActiveAppClient` (System Settings in front, quitting, its window frames), `FileClient` (`open`: "Check for Updates" opens the latest release in the browser; `info`, `folderSize` and `remove`: a feature's data for its page and Erase Data); `OutsideActivity` to keep the window open during drags out of it, Quick Look and the folder picker; `QuickLook`, which the window hands the Quick Look panel to.

## QA mode (debug builds)
- Gives App `ShellController.prepareQA()`, called first in main.swift, and `isSameQARun(pid:)`, so one instance runs per QA run.
- `start()` first installs QA's window guard (`QA.guardWindows()`): any window of the run that lands on a display is a violation and is ordered out.
- Registers with VortexPlatform's `QA`: the window `notch` (mode: why it is open), the state section `shell` (with the open page of Settings › Features, the keyboard's layout and each pressed key's wash), and the commands `entry`, `tab` (`id=catalog` and `id=catalog:<feature id>` too; `id=settings section=features feature=<id>` for a feature's page in Settings), `catalog`, `feature` (`add|remove|erase|home|settings id=`; `home` is "Add to Home", `settings` the page's Settings), `launch` (`set=`: the next launch's verdict, read once from `.qa/next-launch`), `keyboard` (`press=start|stop`, and `key=<name>` for a key of the locked keyboard, through `QA.pressKey`), `screens` and `indicator` (QA/ShellQA.swift).
- Also the command `perm` and the state section `permissions` over VortexPlatform's `QAPermissions` (QA/PermissionsQA.swift), and `QA.isShowing`: what shows, so features refuse presses of hidden controls; `featureSettings` shows while a feature's page in Settings › Features does, whichever feature's it is.
- The menu bar menu's items have identifiers (continueSetup, open, settings, quit), which `entry kind=menu item=` names; a hidden item can't be chosen.
- The onboarding registers the windows `onboarding` and `onboarding-panel`, the state section `onboarding` (page, mode, rows, Skip/Next, completed, saved progress, frames, the Features page's `choosable` and `chosen`) and the command `onboarding press=…|open|reset` (`press=feature:<id>` checks a feature).
- In a QA run the window opens off the displays without animation and never takes the keyboard or the front; there are no ears, no menu bar icon and no click monitor, and the displays are `QA.screens`.
- A visible QA run (`--qa-visible`) opens the window and draws the ears and flashes where plain Vortex does, with the animations, but the pointer passes through them and nothing takes the keyboard.
- A QA run listens to no `…debug.*` notification.
