# VortexCore

Shared ground for the shell and all features. Depends on The Composable Architecture and GRDB.

| File | What it covers |
| --- | --- |
| FeatureModule.swift | the contract every feature implements: id, title, symbol, tab, settings, taking files, starting and stopping, Home widget, the permissions it needs with their reasons (`permissionNeeds`), its own onboarding page (OnboardingStep.swift: `OnboardingStep`, and `onboardingStepsDone`, where a feature inserts its id once its step is done, for Next instead of Skip) |
| HomeWidget.swift | `HomeSlot` and `HomeWidget`: a feature's part of Home; the environment values `homeWidgets` and `keyboardCleaning`, the shell's action behind Home's keyboard button (nil: no button) |
| NotchIndicator.swift | indicators for the closed notch, how they fill the ears and which feature owns each ear, colored flashes, alarms that flash until seen, and the shared key `notchIndicators` |
| Permissions.swift | `Permission` (title, what its warning says, whether a grant waits for a relaunch, whether macOS grants it in its own prompt), `PermissionStatus`, `PermissionNeed`; the shared keys `permissionStatuses` and `appBlocked`, written only by the shell, empty and false until its first read (a missing status is unknown: no warning); `PermissionPage`, which opens the shell's page for a permission: live, `open` leaves the request in a channel inside the app that the shell drains with `requests()` from launch on, as feature stores aren't children of its store, and only the latest request waits for it; unimplemented in tests |
| Database.swift, QALaunch.swift | `DataFolder` (~/Library/Application Support/Vortex; in a debug build started with `--qa <name>`, Vortex QA/<name>, read by `QALaunch` with its options; a bad `--qa…` stops the app), under which everything a feature keeps goes; the one SQLite database `@Dependency(\.database)`, `migrate(_:)`, and `@Dependency(\.databaseIsOnDisk)`: false when the file didn't open and features work in memory |
| AppPreferences.swift | theme and language values |
| DesignSystem/ | monochrome palette, window metrics and levels, environment values (`notchCutout`, `isWindowOpen`), switch, capsule buttons, segmented picker, settings row, hairline, short ages `Text(age:now:)` (strings in Resources/), `ColorValue` (a color to store and send); the one other color, `VortexColor.warning` (system yellow), drawn by `WarningMark`: a triangle, or a dot for the sidebar, which given a permission says "Notifications are off" as a tooltip and to VoiceOver; `PermissionMark` (yellow only for `notGranted`, ↻ for `grantedAfterRestart`) and `PermissionRows`, a feature's settings rows with "Turn on" or "Restart Vortex" |

- A feature never asks macOS for a permission: it reads the statuses and calls `permissionPage.open(_:)`; while `appBlocked`, its own shortcut does that instead of its work.
