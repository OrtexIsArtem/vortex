# Contracts

## Provides
- `ShellController` — created by App at launch: `start()`, and `saveSettings()` when the app quits.
- To feature tabs: `notchCutout` and `isWindowOpen` in the SwiftUI environment.

## Owns
- The notch window, the ears around the notch and the menu bar icon (Window/). Nothing outside the shell opens or closes the window.

## Uses
- FeatureRegistry: every `FeatureModule` — descriptor, `makeTab()`, `makeSettings()`, `acceptsFileDrops`, `setEnabled(_:)`.
- VortexCore: `FeatureModule`, `@Shared(.notchIndicators)`, design system, `AppTheme`, `AppLanguage`.
- VortexPlatform: `HotkeyClient`, `LaunchAtLoginClient`, `SystemClient`.

## Not yet wired
- Files dropped on the menu bar icon — stage 2, with the Shelf and a contract that hands files to a feature.
- Keeping the window open while something is dragged out of it — stage 2, with a drag source in Platform.
- Clicking an ear to reach its feature — stage 3, with the timer.
