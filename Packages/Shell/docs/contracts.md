# Contracts

## Provides
- `ShellController` — created by App at launch: `start()`, `receiveFiles(_:)` for files opened with Vortex, and `saveSettings()` when the app quits.
- To feature tabs: `notchCutout` and `isWindowOpen` in the SwiftUI environment.
- Puts the Home widgets of enabled features, in sidebar order, into the environment of the tab content (`homeWidgets`).

## Owns
- The notch window, the ears around the notch and the menu bar icon (Window/). Nothing outside the shell opens or closes the window.

## Uses
- FeatureRegistry: every `FeatureModule` — descriptor, `makeTab()`, `makeSettings()`, `makeHomeWidget()`, `acceptsFileDrops`, `receiveFiles(_:)`, `setEnabled(_:)`.
- VortexCore: `FeatureModule`, `@Shared(.notchIndicators)`, design system, `AppTheme`, `AppLanguage`.
- VortexPlatform: `HotkeyClient`, `LaunchAtLoginClient`, `SystemClient`; `OutsideActivity` to keep the window open during drags out of it, Quick Look and the folder picker; `QuickLook`, which the window hands the Quick Look panel to.

## Not yet wired
- Clicking an ear to reach its feature — stage 3, with the timer.
