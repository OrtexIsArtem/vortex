# Vortex — rules for Claude

Personal macOS utility that lives in the notch and the menu bar.
Product spec: docs/spec.ru.md (Russian). Plan and progress: docs/plan.md. Module map: docs/README.md.

## Stack
- Swift 6 language mode with strict concurrency. SwiftUI + The Composable Architecture 1.x (pinned; do not move to 2.0 until it is stable).
- macOS 14+, Apple silicon only. Offline by design: no analytics, no auto-updates, no network.
- XcodeGen: project.yml is the source of truth for Vortex.xcodeproj. Never hand-edit the .xcodeproj — change project.yml, run `make project`, commit both.
- All modules live in the local package Packages/ (VortexKit, see Packages/Package.swift).

## Commands
- `make project` — regenerate Vortex.xcodeproj from project.yml
- `make build` — compile the app without signing (for checks)
- `make test` — run package tests
- `make check` — no-network rule (also runs as a build phase)
- `make open` — regenerate and open in Xcode
- `make install-cli` — link the `vortex` command (Tools/CLI) into /opt/homebrew/bin
- `scripts/strings.py <Localizable.xcstrings> <entries.json>` — add keys with their uk translations to a String Catalog
- `make build` skips macro validation; in the Xcode UI the first build asks to "Trust & Enable" the TCA macro packages once.
- To check the running app without the pointer, use the debug notifications described in App/docs/README.md.

## Architecture
1. A feature never imports another feature. Features talk only through contracts in VortexCore or through the app shell.
2. A feature brings everything of its own: sidebar tab, settings, Home widget, database tables prefixed with its id, their migrations, its docs.
3. New feature: copy Features/_Template to Features/<Name>, rename the module and types, add "<Name>" to `features` in Packages/Package.swift and its import and entry to Features/Registry. Removing a feature = deleting its folder and those lines; everything else must still build.
4. If nobody fulfils a contract, the caller hides the control (e.g. "Make key" disappears without Secrets).
5. System APIs (pasteboard, screenshots, files, Keychain, hotkeys) only through clients in VortexPlatform, so every feature can be tested with substituted clients.
6. The notch window and the menu bar icon belong to the shell; features never open or close the window. A feature shows status in the notch by writing its own entry to `@Shared(.notchIndicators)` from its reducer.
7. A feature starts and stops its background work in `FeatureModule.setEnabled`. Its tab stays mounted while the window is closed, so work that should run only while visible goes into `.task(id: isWindowOpen)`.
8. Each module declares its own shortcuts (`extension Hotkey { static let x = Hotkey("x") }`), listens with `HotkeyClient.presses` and puts `HotkeyRecorder` in its own settings.
9. Data lives in DataFolder (~/Library/Application Support/Vortex). A feature's tables go in the shared database (`@Dependency(\.database)`), named `<id>_…`, created by its own `DatabaseMigrator` (migrations `<id>.v1`, `<id>.v2`…) before its first query; its files go in DataFolder/<Name>/; its settings in DataFolder/<id>.json (`@Shared(.fileStorage)`).

## Working rules
- One task = one feature. Don't touch other modules.
- Network code only in Features/Secrets; `make check` fails the build otherwise.
- After every change: build and run the tests of the module you touched.
- Nothing heavy on the main thread: OCR, database and previews run in the background. Track the cursor near the notch with system events, never by polling.
- Library versions are pinned in Package.resolved. Update them only when explicitly asked.
- UI strings in Ukrainian and English: `Text("…", bundle: .module)` / `String(localized: "…", bundle: .module)` with a uk translation in the module's Resources/Localizable.xcstrings; a feature title is `LocalizedStringResource("…", bundle: .atURL(Bundle.module.bundleURL))`. Code, comments and docs in English.
- `swift test` does not compile String Catalogs (Xcode does), so tests never assert translated text.
- A public reducer must be declared `Sendable` explicitly (Swift 6 does not infer it for public types).
- `.onChange` must wrap `BindingReducer` too (put both in `CombineReducers`), otherwise binding changes are missed.
- Design reference: the canvas linked in docs/README.md. Monochrome by default, minimal, large click targets.

## Signing
- Bundle id: io.github.ortexisartem.vortex.

## Git
- Commits are authored by the repository owner only. Never add Co-Authored-By trailers or "Generated with" lines to commits or pull requests.
- Branch `main`; small commits with a clear message in English.

## Feature docs
Each feature keeps short docs next to its code: docs/README.md (map, ≤15 lines), behavior.md, settings.md, data.md, contracts.md (≤60 lines each). Plain language, one checkable rule per line. Core, Platform and App have docs/README.md too.

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

Read a file once per session. After a change ask two questions: does the change contradict the docs (fix that line)? Is there a new rule worth knowing (add one line)? If both answers are no, leave the docs alone. docs/README.md at the root is read only when a change spans several modules.
