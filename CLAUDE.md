# Vortex — rules for Claude

A macOS utility that lives in the notch and the menu bar. Setup, commands, the module map and the architecture are in CONTRIBUTING.md. Read it first.

## Stack
- Swift 6 language mode with strict concurrency. SwiftUI and The Composable Architecture 1.x, pinned; don't move to 2.0 until it is stable.
- macOS 14+, Apple silicon only. Offline by design: no analytics, no auto-updates, no network.
- XcodeGen: project.yml is the source of truth for Vortex.xcodeproj. Never hand-edit the .xcodeproj. Change project.yml, run `make project`, and commit both.
- Signing comes from Config/Local.xcconfig, which git ignores. Never commit a team ID.
- All modules live in the local package Packages/ (VortexKit, see Packages/Package.swift).

## Commands
- `make project`: regenerate Vortex.xcodeproj from project.yml.
- `make build`: compile the app without signing, into build/ and as `io.github.ortexisartem.vortex.check`, so it never replaces the signed app.
- `make test`: run the package tests.
- `make check`: allows network APIs only in Secrets, and processes only in Platform's CommandClient and SystemClient. It also runs as a build phase.
- `make hooks`: run `make check` and the package tests before every push.
- `scripts/strings.py <Localizable.xcstrings> <entries.json>`: add keys with their uk translations to a String Catalog.
- QA mode (`--qa <name>`, `scripts/qa`) runs an isolated debug copy. See App/docs/README.md. Never drive or relaunch the user's own running Vortex.

## Architecture
1. A feature never imports another feature. Features talk only through contracts in VortexCore or through the app shell.
2. A feature brings everything of its own: its sidebar tab, settings, Home widget, database tables prefixed with its id, their migrations, and its docs.
3. To add a feature:
   - copy Features/_Template to Features/<Name>, then rename the module and types;
   - add "<Name>" to `features` in Packages/Package.swift;
   - add its import and entry to Features/Registry.

   Removing a feature means deleting its folder and those lines; everything else must still build.
4. If nobody fulfils a contract, the caller hides the control.
5. System APIs go only through clients in VortexPlatform, so every feature can be tested with substituted clients. That covers the pasteboard, screenshots, files, Keychain, hotkeys and permissions.
6. The notch window and the menu bar icon belong to the shell; features never open or close the window. A feature shows status in the notch by writing its own entry to `@Shared(.notchIndicators)` from its reducer.
7. A feature asks for a macOS permission only through `PermissionPage`, and declares what it needs in `permissionNeeds`.
8. A feature starts and stops its background work in `FeatureModule.setEnabled`. Its tab stays mounted while the window is closed, so work that should run only while visible goes into `.task(id: isWindowOpen)`.
9. Each module declares its own shortcuts (`extension Hotkey { static let x = Hotkey("x") }`), listens with `HotkeyClient.presses`, and puts `HotkeyRecorder` in its own settings.
10. Data lives in DataFolder (~/Library/Application Support/Vortex):
    - A feature's tables go in the shared database (`@Dependency(\.database)`), named `<id>_…`. Its own `DatabaseMigrator` creates them, with migrations `<id>.v1`, `<id>.v2`…, before its first query.
    - Its files go in DataFolder/<Name>/.
    - Its settings go in DataFolder/<id>.json (`@Shared(.fileStorage)`).

## Working rules
- One task = one feature. Don't touch other modules.
- After every change, build and run the tests of the module you touched.
- Nothing heavy on the main thread: OCR, the database and previews run in the background. Track the cursor near the notch with system events, never by polling.
- Library versions are pinned in Package.resolved. Update them only when explicitly asked.
- UI strings are in English and Ukrainian:
  - use `Text("…", bundle: .module)` or `String(localized: "…", bundle: .module)`, with a uk translation in the module's Resources/Localizable.xcstrings;
  - a feature title is `LocalizedStringResource("…", bundle: .atURL(Bundle.module.bundleURL))`;
  - code, comments and docs are in English.
- `swift test` does not compile String Catalogs (Xcode does), so tests never assert translated text.
- A public reducer must be declared `Sendable` explicitly (Swift 6 does not infer it for public types).
- `.onChange` must wrap `BindingReducer` too (put both in `CombineReducers`), otherwise binding changes are missed.
- Design: monochrome by default, minimal, large click targets.
- Commits: small, with a clear message in English.

## Feature docs
Each feature keeps short docs next to its code:
- docs/README.md: the map, 15 lines or fewer;
- behavior.md, settings.md, data.md and contracts.md: 60 lines or fewer each.

Write them in plain language, one checkable rule per line. Core, Platform and App have docs/README.md too.

Read docs only when the change touches them:

| Change | Read | Update |
| --- | --- | --- |
| Colors, spacing, fonts, icons, label text | nothing | nothing |
| Behavior: what happens after an action | README, then behavior.md | behavior.md |
| Settings: new, removed or default value | README, then settings.md | settings.md |
| Storage: table, field, retention | README, then data.md | data.md |
| Link to another feature or the system | README, then contracts.md | contracts.md |
| New feature | — | copy docs from _Template and fill them |
| Removed feature | — | nothing, docs go with the folder |

After a change, ask two questions:
1. Does the change contradict the docs? Fix that line.
2. Is there a new rule worth knowing? Add one line.

If both answers are no, leave the docs alone.
