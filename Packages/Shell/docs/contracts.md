# Contracts

## Provides
- `ShellController` — starts the shell; created by App at launch.

## Uses
- FeatureRegistry: every `FeatureModule` — its descriptor, `makeTab()`, `makeSettings()` and `acceptsFileDrops`.
- VortexCore: `FeatureModule`, `NotchIndicatorCenter`, design system, `AppTheme`, `AppLanguage`.
- VortexPlatform: `WindowClient` (events, present, dismiss, menu bar icon), `HotkeyClient`, `LaunchAtLoginClient`, `SystemClient`, `WindowController.install`.

## Not yet wired
- Files dropped on the menu bar icon are ignored until a feature accepts files (Shelf, stage 2).
- Dragging out of a tab must send `dragOutChanged`; features that start drags call it from stage 2.
