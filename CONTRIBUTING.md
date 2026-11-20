# Contributing to Vortex

Vortex is a native macOS app in Swift 6 with SwiftUI and [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture), built for macOS 14+ on Apple silicon. Every module lives in one local Swift package, `Packages/`.

## Run the project
1. Install Xcode (the version that ships the macOS 26 SDK or newer) and [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
2. Clone the repository: `git clone https://github.com/OrtexIsArtem/vortex.git && cd vortex`.
3. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, which git ignores, and set `DEVELOPMENT_TEAM` to your team ID.
   - A free Personal Team works. Add your Apple ID in Xcode › Settings › Accounts, then build once in Xcode with your team chosen, so Xcode creates your certificate.
   - To find your team ID, run `security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject` and read the value after `OU=`. The ID in parentheses in the certificate's name is not the team ID.
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
| VortexShell | Packages/Shell | the notch window, menu bar icon, sidebar, settings, onboarding, the utilities dock and the window covers |
| VortexCore | Packages/Core | contracts between the shell and features (including the permissions they need), notch indicators, the database, the design system |
| VortexPlatform | Packages/Platform | system clients:<br>• hotkeys, pasteboard, files, Quick Look<br>• screen capture, text recognition<br>• keychain, commands in the user's shell<br>• permissions, login item, QA mode |
| FeatureRegistry | Packages/Features/Registry | the features the app ships, in sidebar order |
| FeatureHome | Packages/Features/Home | Home: lays out the widgets the features hand over |
| FeatureTimer | Packages/Features/Timer | one timer at a time, with the countdown in the notch |
| FeatureClipboard | Packages/Features/Clipboard | clipboard history: the last copies plus pinned ones |
| FeatureShelf | Packages/Features/Shelf | files put aside to drag into other apps |
| FeatureTasks | Packages/Features/Tasks | tasks from the screen: screenshot, recognized text, source |
| FeatureKeyboardCleaning | Packages/Features/KeyboardCleaning | a utility: every key locked while the keyboard is wiped, its lock screen over the window |
| FeatureScreenText | Packages/Features/ScreenText | a utility: text off the screen, a frame on the frozen screen, its text or QR code copied |
| FeatureSecrets | Packages/Features/Secrets | keys Claude uses by name, through a local MCP server |
| FeatureTemplate | Packages/Features/_Template | the template for a new feature |
| FeatureUtilityTemplate | Packages/Features/_UtilityTemplate | the template for a new utility |
| Tools | Tools/ | the `vortex` CLI |

Each module keeps short docs next to its code in `docs/`:
- `README.md`, the map of the module;
- `behavior.md`, `settings.md`, `data.md`, `contracts.md`.

Read the module's README first. When a change contradicts a line in these docs, fix the line in the same change.

## Architecture rules
1. A feature never imports another feature. Features talk only through contracts in VortexCore, or through the shell.
2. A feature brings everything of its own: its sidebar tab (a utility has none, see "Make a utility"), settings, Home widgets, utility actions, database tables (prefixed with its id), migrations and docs. Its settings (`makeSettings()`) show on its own page in Settings › Features, after the shortcut that opens its tab or those of its utility actions.
3. To add a feature, copy `Features/_Template` (a utility: `Features/_UtilityTemplate`) to `Features/<Name>` and rename the module and its types. Then add `"<Name>"` to `features` in `Packages/Package.swift`, and its entry to `Features/Registry`. Removing a feature means deleting its folder and those lines; everything else must still build.
4. If nobody provides a contract, the caller hides the control.
5. System APIs (pasteboard, screenshots, files, keychain, hotkeys, permissions) are reached only through clients in VortexPlatform, so every feature can be tested with substituted clients.
6. The notch window and the menu bar icon belong to the shell. A feature shows status in the notch by writing its own entry to `@Shared(.notchIndicators)`.
7. A feature starts and stops its background work in `FeatureModule.setEnabled`.
8. A feature asks for a macOS permission through `PermissionPage`, never by itself, and declares what it needs in `permissionNeeds`.
9. Data lives in `~/Library/Application Support/Vortex`:
   - a feature's tables go in the shared database, named `<id>_…`, with migrations `<id>.v1`, `<id>.v2`…; a test in the feature proves it (`migrator.names()`, see `_Template`), as Erase Data finds them by the id;
   - its settings go in `<id>.json`, its files in its folder (`dataFolder`);
   - whatever it keeps elsewhere (keychain items, its own shortcuts) its `eraseData()` deletes.
10. Network code lives only in Features/Secrets, and processes start only in Platform's `CommandClient` and `SystemClient`. `make check` fails the build otherwise.

## The catalog
Users add features from the catalog; a feature that isn't added runs no code. Describe yours in its module:
- `summary` (one line for its card), `details` (two to four lines for its page), `author` (a name or a GitHub handle), `keeps` (what it stores, in one line), `dataFolder`, `eraseNote` if erasing does more than delete its data, `hasOnboardingStep` if it has a setup page.
- `isRecommended` puts it on a fresh install and marks it "Recommended": only the maintainer sets it. `isBeta` marks it "Beta".
- Media: a 5–10 s HEVC video of the feature at work and a still, in `Sources/Resources/Catalog`, set in `preview`; the interface in them is in English. `make check` keeps each feature's media under 1.5 MB.
- Pausing a feature for a release: set `suspension` with the reason the catalog shows; it stays in the build and in users' lists but doesn't run. A feature that doesn't compile is left out of the build instead: remove its name from `features` in `Packages/Package.swift` and its line from `Features/Registry`, and keep its folder.

## Make a utility
A utility does one clear thing and needs no screen of its own, as Screen Text (the text in a frame on the screen) and Keyboard Cleaning do. It has no tab: its button lives in Home's utilities dock, and a user who doesn't want it removes it with one switch in the catalog's Utilities section. Make one when your idea is an action, not a place to look at; make a feature (above) when it needs a tab.

`Packages/Features/_UtilityTemplate` is the full working example: one action that says hello in the closed notch, its shortcut, its test and its docs. Copy it to `Features/<Name>`, rename the module and its types, then add `"<Name>"` to `features` in `Packages/Package.swift` and its line to `Features/Registry`, as for a feature.

- **The kind.** Conform to `UtilityModule` rather than `FeatureModule`: its kind is `.utility` by its type, and it writes no `makeTab()`, which a plain `FeatureModule` must. The shell gives it no sidebar icon, no Open on its catalog page (Settings is the primary button there) and no shortcut that opens a tab. The catalog, Settings › Features and the onboarding's Features page list it in their Utilities group.
- **Its action.** Return it from `makeUtilityActions()`: an id `<id>.<name>`, an SF Symbol, a label ("Copy Text") and a help line ("Copy text from the screen"), the permission its yellow mark names, the name of its own `Hotkey`, and what a click does. A utility offers one action, two at most; each is a round button in the dock, in catalog order, its tooltip the label and the shortcut's keys.
- **The window.** Say what the window must be first (`WindowNeed`): `.closed` for an action that works on the screen, as Screen Text's frame does; `.open` for one whose own screen covers the window; `.unchanged` when it doesn't matter. The shell sees to it, puts the dock away, then runs the action. A utility never opens or closes the window itself.
- **A screen over the window.** An `.open` action may cover the whole window while it works, as keyboard cleaning's lock screen does: return the view from `makeWindowCover()`, and put `WindowCover(feature: id)` in `@Shared(.windowCover)` from the reducer as the work starts, nil as it ends, however it ends; if the utility stops first, the shell takes it down. Meanwhile the window stays open and nothing closes it; when the cover goes, the window closes. `holdsKeyboard` keeps Vortex in front, dropping every key that reaches it.
- **The shortcut.** Declare its `Hotkey` (`extension Hotkey { static let sayHello = Hotkey("sayHello") }`) and name it in the action: the shell records it on the utility's page in Settings › Features, first, and listens for it while the utility runs. Don't add a `HotkeyRecorder` for it yourself, and don't listen for it.
- **Feedback.** Say what happened in the closed notch with your own entry in `@Shared(.notchIndicators)`, for a moment, as Screen Text's "Copied · 2 lines" does.
- **Permissions and settings** work as a feature's: `permissionNeeds` (the onboarding asks for them only while the utility is added), `PermissionPage` instead of asking macOS, `makeSettings()` under the shortcut.
- **Tests.** Keep the template's: the action follows `UtilityAction.problems`, its window need is the one you mean, and its reducer does what the button promises. `FeatureRegistryTests` checks every shipped utility offers an action.
- A feature with a tab may offer utility actions too; their buttons come first in the dock.

## Make a widget for Home
A widget shows a feature on Home: in the row next to the notch, or on the grid of 4×2 cells under it.
- A feature offers at most two.
- On a fresh install, Home's first layout places the widgets of the features chosen during setup. After that the user places them: "Add to Home" on the feature's page in Features puts its first widget on Home, and Home's editor adds, moves, resizes and removes widgets.
- Home draws the card, owns the grid and the editor, and decides where each widget goes. Your widget draws only its content.

`Packages/Features/_Template` is the full working example: a widget in two sizes, its previews, its test and its docs. Home's own rules, such as the first layout and the editor, are in `Packages/Features/Home/docs/behavior.md`.

### Sizes
The grid's cells are 143×182 pt, 12 pt apart (`HomeGrid`). The window is the same size on every Mac, so every size is exact points. Home insets a widget 14 pt from the top and bottom of its card and 16 pt from its sides, which leaves this room inside:

| Size | Cells | Card (pt) | Room inside (pt) |
| --- | --- | --- | --- |
| Small | 1×1 | 143×182 | 111×154 |
| Medium | 2×1 | 298×182 | 266×154 |
| Wide | 4×1 | 608×182 | 576×154 |
| Large | 2×2 | 298×376 | 266×348 |
| Full | 4×2 | 608×376 | 576×348 |

- A widget on the grid lists one to three sizes, in the order it prefers. The first is its default: Home's first layout and "Add to Home" place it at that size, or at the next one when the first fits nowhere, and the editor's panel adds it at that size unless the user picks another.
- A widget can take the row next to the notch instead. The row holds one widget, Timer's by default. There it has no card and gets the whole row, 624×52 pt; `homeWidgetSize` is nil, and `@Environment(\.notchCutout)` says where the notch cuts in, nil where there is none.

### Step 1: declare it
Return the widget from the module's `makeHomeWidgets()`. `_Template` offers one, Small or Medium:

```swift
public static func makeHomeWidgets() -> [HomeWidget] {
  [
    HomeWidget(
      id: "template.count",
      feature: id,
      title: LocalizedStringResource("Count", bundle: .atURL(Bundle.module.bundleURL)),
      place: .grid([.small, .medium]),
      view: TemplateHomeWidget(store: store)
    ),
  ]
}
```

- `id` is `<feature id>.<name>`. Home's saved layout finds the widget by it, so don't change it once the widget ships.
- `title` is the widget's name in the editor, translated like any UI string.
- `place` is `.grid` with its sizes in order, or `.notchRow`.
- `view` takes the feature's store, the same one its tab uses.

### Step 2: the view
- Read the size from `@Environment(\.homeWidgetSize)` and fit each size you list. `_Template`'s widget adds its Increment button at Medium; Shelf's lays its files out six across at Wide and three across at the others.
- Draw no card or background of your own. Home draws the card under the view, insets it, clips whatever spills over, and in the editor takes the pointer from it.
- Keep to the app's monochrome design: colors from `VortexColor`, the type sizes the app already uses (the widgets on the grid start with the feature's name in 12 pt `secondaryText`), buttons in `.quietCapsule` or `.primaryCapsule`. Make what's clickable large: whole rows and capsule buttons, not bare icons.

**Keep the widget's state in the feature's store, not in `@State`.** The shell calls `makeHomeWidgets()` once and keeps the view, but the view can show in two places at once: on Home and, while the editor is open, as its preview in the editor's panel. Each place is a copy with its own `@State`, and each runs its own `.onAppear`, `.task` and `.onDisappear`. So `@State` suits only what one copy shows alone, such as a drop highlight, and whatever the widget does on appearing or disappearing must be safe to run once per copy. Clipboard's widget sends its tab's `.tabShown` action when it appears, so its preview in the editor's panel resets the search in the Clipboard tab; users don't notice, as the tab resets its search whenever it shows.

### Step 3: preview every size
Add a `#Preview` for each size the widget lists. `HomeWidgetPreview` draws Home as the window shows it, every cell outlined and the widget at its real size on its card; a widget of the notch row shows in its row, and `size` is ignored. Home clips what spills over a card and nothing warns, so these previews are where you see it.

```swift
#Preview("Widget, Small") {
  HomeWidgetPreview(TemplateModule.makeHomeWidgets()[0], size: .small)
}

#Preview("Widget, Medium") {
  HomeWidgetPreview(TemplateModule.makeHomeWidgets()[0], size: .medium)
}
```

### Step 4: test the rules
`HomeWidget.problems` lists what breaks Home's rules: more than two widgets, an id that doesn't start with `<feature id>.` or comes twice, a widget on the grid without one to three sizes, a size named twice. `_Template`'s tests check that it finds none; keep that test for your feature:

```swift
@Test
func templateWidgetsFollowTheRules() {
  let widgets = TemplateModule.makeHomeWidgets()
  #expect(!widgets.isEmpty)
  #expect(HomeWidget.problems(widgets, feature: TemplateModule.id).isEmpty)
}
```

Once the feature is in `Features/Registry`, the shell's `FeatureRegistryTests` runs the same check on it.

### Step 5: docs
Add a line about the widget to two of the feature's docs:
- `behavior.md`: what it shows at each size, as `_Template`'s "The widget on Home shows the counter; at Medium it has Increment too."
- `contracts.md`: its id, name and sizes in order, as Clipboard's "Home widget `clipboard.history` ("History") on the grid: Large 2×2 first, the size Home's first layout gives it, then Medium 2×1."

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
- Before you open a pull request, run `make check` and `make test`. CI runs both on pushes to `main` and on every pull request, and also builds the release configuration.
- If your change touches a screen, add a QA snapshot or a screenshot.

## Releasing
1. Bump `MARKETING_VERSION` in `project.yml`, run `make project`, commit, and push `main`, so the commit goes through CI.
2. Tag that commit and push the tag: `git tag v0.2.0 && git push origin v0.2.0`.
3. GitHub Actions (`.github/workflows/release.yml`) runs the checks and tests, builds the app versioned by the tag, signs it with the Vortex certificate (`scripts/sign-release.sh`) and checks that it launches. It zips the app with `LICENSE` and the third-party notices, and creates a **draft** GitHub Release.
4. Download the zip, try it on your Mac, then publish the draft. The release isn't notarized; README.md tells users how to open it.

Every release is signed with one self-signed certificate, "Vortex Release Signing", valid until November 2036. macOS ties Vortex's permissions to it, so they survive updates. It lives in the repository's secrets `VORTEX_SIGNING_P12` (the .p12, base64) and `VORTEX_SIGNING_PASSWORD`; the maintainer keeps a copy. `scripts/sign-release.sh` and `site/public/install.sh` pin its SHA-1 and refuse any other. A new certificate costs every user their permissions once more: change it only when this one expires, in all three places.
