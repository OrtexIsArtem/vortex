# Contributing to Vortex

Vortex is a native macOS app in Swift 6 with SwiftUI and [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture), built for macOS 14+ on Apple silicon. Every module lives in one local Swift package, `Packages/`.

## Run the project
1. Install Xcode (the version that ships the macOS 26 SDK or newer) and [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
2. Clone the repository: `git clone https://github.com/OrtexIsArtem/vortex.git && cd vortex`.
3. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, which git ignores, and set `DEVELOPMENT_TEAM` to your team ID.
   - A free Personal Team works: Xcode › Settings › Accounts, add your Apple ID, and the team ID shows under the team.
   - If Xcode says the bundle id belongs to another team, set `PRODUCT_BUNDLE_IDENTIFIER` there too.
4. Run `make open`, then press Run in Xcode. The first build asks you to "Trust & Enable" the TCA macro packages once.
5. Vortex starts with its onboarding. It sits in the notch; on a Mac without one it's the icon in the menu bar.
6. Optional: `make hooks` runs the checks and the tests before every push.

For daily use, run `make install` instead of a debug session. A debug session ends when the Mac sleeps for a while.

## Where to start in the code
- **The app's startup:** `App/Sources/main.swift` → `AppDelegate` → `ShellController` in `Packages/Shell/Sources/` → `ShellFeature`. `ShellFeature` is the root reducer for the window, onboarding and permissions.
- **The feature contract:** `Packages/Core/Sources/FeatureModule.swift` is the contract every feature implements. `Packages/Features/Registry` lists the features in sidebar order.
- **A feature from start to end:** `Packages/Features/Timer` is the smallest complete feature. `Packages/Features/_Template` is the one to copy.
- **System APIs:** `Packages/Platform/Sources/Clients/` has one client per system API.
- **Permissions:** `Packages/Core/Sources/Permissions.swift` holds the contract, and `Packages/Platform/Sources/Permissions/` reads what macOS says.
- **The onboarding:** `Packages/Shell/Sources/Onboarding/`.
- **Each module's `docs/README.md`:** a 15-line map of the module.

`project.yml` is the source of truth for `Vortex.xcodeproj`. Change `project.yml`, run `make project`, and commit both. Changes made in the Xcode UI are lost on the next `make project`.

| Command | What it does |
| --- | --- |
| `make project` | regenerate Vortex.xcodeproj from project.yml |
| `make open` | regenerate and open in Xcode |
| `make build` | compile the app without signing, into `build/`, under a bundle id of its own |
| `make install` | build a release, put it in /Applications and open it |
| `make test` | run the package tests |
| `make check` | no network code outside Secrets, and no processes outside Platform's command and system clients |
| `make hooks` | run `make check` and the tests before every push |
| `make install-cli` | link the `vortex` command (`vortex shelf add <files>`) into /opt/homebrew/bin |

## Modules
| Module | Path | Purpose |
| --- | --- | --- |
| App | App/ | the entry point: starts the shell |
| VortexShell | Packages/Shell | the notch window, menu bar icon, sidebar, settings, onboarding and keyboard cleaning |
| VortexCore | Packages/Core | contracts between the shell and features (including the permissions they need), notch indicators, the database, the design system |
| VortexPlatform | Packages/Platform | system clients:<br>• hotkeys, pasteboard, files, Quick Look<br>• screen capture, text recognition<br>• keychain, commands in the user's shell<br>• permissions, login item, QA mode |
| FeatureRegistry | Packages/Features/Registry | the features the app ships, in sidebar order |
| FeatureHome | Packages/Features/Home | Home: lays out the widgets the features hand over |
| FeatureTimer | Packages/Features/Timer | one timer at a time, with the countdown in the notch |
| FeatureClipboard | Packages/Features/Clipboard | clipboard history: the last copies plus pinned ones |
| FeatureShelf | Packages/Features/Shelf | files put aside to drag into other apps |
| FeatureTasks | Packages/Features/Tasks | tasks from the screen: screenshot, recognized text, source |
| FeatureSecrets | Packages/Features/Secrets | keys Claude uses by name, through a local MCP server |
| FeatureTemplate | Packages/Features/_Template | the template for a new feature |
| Tools | Tools/ | the `vortex` CLI |

Each module keeps short docs next to its code in `docs/`:
- `README.md`, the map of the module;
- `behavior.md`, `settings.md`, `data.md`, `contracts.md`.

Read the module's README first. When a change contradicts a line in these docs, fix the line in the same change.

## Architecture rules
1. A feature never imports another feature. Features talk only through contracts in VortexCore, or through the shell.
2. A feature brings everything of its own: its sidebar tab, settings, Home widget, database tables (prefixed with its id), migrations and docs.
3. To add a feature, copy `Features/_Template` to `Features/<Name>` and rename the module and its types. Then add `"<Name>"` to `features` in `Packages/Package.swift`, and its entry to `Features/Registry`. Removing a feature means deleting its folder and those lines; everything else must still build.
4. If nobody provides a contract, the caller hides the control.
5. System APIs (pasteboard, screenshots, files, keychain, hotkeys, permissions) are reached only through clients in VortexPlatform, so every feature can be tested with substituted clients.
6. The notch window and the menu bar icon belong to the shell. A feature shows status in the notch by writing its own entry to `@Shared(.notchIndicators)`.
7. A feature starts and stops its background work in `FeatureModule.setEnabled`.
8. A feature asks for a macOS permission through `PermissionPage`, never by itself, and declares what it needs in `permissionNeeds`.
9. Data lives in `~/Library/Application Support/Vortex`:
   - a feature's tables go in the shared database, named `<id>_…`, with migrations `<id>.v1`, `<id>.v2`…;
   - its settings go in `<id>.json`.
10. Network code lives only in Features/Secrets, and processes start only in Platform's `CommandClient` and `SystemClient`. `make check` fails the build otherwise.

## Code
- Swift 6 language mode, strict concurrency. Declare public reducers `Sendable` explicitly.
- Wrap `.onChange` and `BindingReducer` together in `CombineReducers`.
- Keep heavy work off the main thread: OCR, the database and previews.
- Code, comments and docs are in English.
- UI strings are in English and Ukrainian: `Text("…", bundle: .module)` with a `uk` translation in the module's `Resources/Localizable.xcstrings`. `scripts/strings.py` adds keys with their translations. `swift test` doesn't compile String Catalogs, so tests never assert translated text.
- Library versions are pinned in `Package.resolved`.

## Testing
- `make test` runs every package's tests. Use a `TestStore` with substituted clients for reducers.
- QA mode runs an isolated copy of a debug build next to your own Vortex:
  - it has its own data folder and port;
  - macOS permissions and other system services are simulated;
  - its windows are kept off-screen and render snapshots themselves;
  - `scripts/qa` drives it with commands.

  See the QA section of [App/docs/README.md](App/docs/README.md). It never touches your real data, keys, clipboard or permissions.

## Pull requests
- Keep commits small, with clear English messages.
- Before you open a pull request, run `make check` and `make test`. CI runs both on every push and pull request, and also builds the release configuration.
- If your change touches a screen, add a QA snapshot or a screenshot.

## Releasing
1. Bump `MARKETING_VERSION` in `project.yml`, run `make project`, and commit.
2. Tag the commit, for example `git tag v0.2.0`, and push the tag: `git push origin v0.2.0`.

GitHub Actions (`.github/workflows/release.yml`) then builds the app, signs it ad hoc, and publishes `Vortex-v0.2.0.zip` as a GitHub Release. The release isn't notarized. README.md tells users how to open it.
