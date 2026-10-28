# VortexCore

Shared ground for the shell and all features. Depends on The Composable Architecture and GRDB.

| File | What it covers |
| --- | --- |
| FeatureModule.swift | the contract every feature implements: id, title, symbol, tab, settings, taking files, starting and stopping, Home widget, the permissions it needs with their reasons (`permissionNeeds`), its own onboarding page |
| HomeWidget.swift | `HomeSlot` and `HomeWidget`: a feature's part of Home; the environment values `homeWidgets` and `keyboardCleaning`, the shell's action behind Home's keyboard button (nil: no button) |
| NotchIndicator.swift | indicators for the closed notch, how they fill the ears and which feature owns each ear, colored flashes, alarms that flash until seen, and the shared key `notchIndicators` |
| Permissions.swift | `Permission` (title, whether a grant waits for a relaunch, whether macOS grants it in its own prompt), `PermissionStatus`, `PermissionNeed`; the shared keys `permissionStatuses` and `appBlocked`; `PermissionPage`, which opens the shell's page for a permission |
| OnboardingStep.swift | a feature's own onboarding page; the shared key `onboardingStepsDone`, where a feature inserts its id once its step is done (Next instead of Skip) |
| Database.swift | `DataFolder` (~/Library/Application Support/Vortex), the one SQLite database `@Dependency(\.database)`, `migrate(_:)`, and `@Dependency(\.databaseIsOnDisk)`: false when the file didn't open and features work in memory |
| AppPreferences.swift | theme and language values |
| DesignSystem/ | monochrome palette, window metrics and levels, environment values (`notchCutout`, `isWindowOpen`), switch, capsule buttons, segmented picker, settings row, hairline, short ages `Text(age:now:)` (strings in Resources/), `ColorValue` (a color to store and send); the one other color, `VortexColor.warning` (system yellow), drawn by `WarningMark`: a triangle, or a dot for the sidebar |

- Each feature keeps its tables in the shared database, named after its id, and runs its own `DatabaseMigrator` (migration names start with the id) before its first query.
- Tests get an empty in-memory database; `VortexDatabase.inMemory()` makes one by hand.
- Only the shell writes `permissionStatuses` and `appBlocked`. Until its first read the statuses are empty (unknown: no warning) and `appBlocked` is false.
- A feature never asks macOS for a permission: it reads the statuses and calls `permissionPage.open(_:)`; while `appBlocked`, its own shortcut does that instead of its work.
- `PermissionPage` live: `open` leaves the request in a channel inside the app, which the shell drains with `requests()` from launch on, as feature stores aren't children of its store. A request made before that waits, only the latest. Tests: unimplemented.
