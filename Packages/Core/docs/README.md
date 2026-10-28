# VortexCore

Shared ground for the shell and all features. Depends on The Composable Architecture and GRDB.

| File | What it covers |
| --- | --- |
| FeatureModule.swift | the contract every feature implements: id, title, symbol, tab, settings, taking files, starting and stopping, Home widget |
| HomeWidget.swift | `HomeSlot` and `HomeWidget`: a feature's part of Home; the environment values `homeWidgets` and `keyboardCleaning`, the shell's action behind Home's keyboard button (nil: no button) |
| NotchIndicator.swift | indicators for the closed notch, how they fill the ears and which feature owns each ear, colored flashes, alarms that flash until seen, and the shared key `notchIndicators` |
| Database.swift | `DataFolder` (~/Library/Application Support/Vortex; in a debug build started with `--qa <name>`, Vortex QA/<name>), the one SQLite database `@Dependency(\.database)`, `migrate(_:)`, and `@Dependency(\.databaseIsOnDisk)`: false when the file didn't open and features work in memory |
| QALaunch.swift (debug builds only) | `--qa <name>` and its options (`--qa-reduce-motion`, `--qa-release`, `--qa-screens`) read from the launch arguments; any other `--qa…`, a bad name or options without a name stop the app (QA mode itself is VortexPlatform's `QA`) |
| AppPreferences.swift | theme and language values |
| DesignSystem/ | monochrome palette, window metrics and levels, environment values (`notchCutout`, `isWindowOpen`), switch, capsule buttons, segmented picker, settings row, hairline, short ages `Text(age:now:)` (strings in Resources/), `ColorValue` (a color to store and send) |

- Each feature keeps its tables in the shared database, named after its id, and runs its own `DatabaseMigrator` (migration names start with the id) before its first query.
- Tests get an empty in-memory database; `VortexDatabase.inMemory()` makes one by hand.
- Everything a feature keeps goes under `DataFolder.url`, never a path of its own: that is what keeps a QA run apart from the user's data.
