# Contracts

## Provides
- `TemplateModule` — the FeatureModule entry point for the registry: id, title, symbol, `makeTab()`.
- Optional, when needed: `makeSettings()`, `makeHomeWidget()`, `acceptsFileDrops`, `setEnabled(_:)` to start and stop background work.

## Uses
- VortexCore: `FeatureModule`, design system; `@Shared(.notchIndicators)` to show something in the notch.
- VortexPlatform: nothing yet. Own shortcuts: `extension Hotkey` plus `HotkeyClient.presses`.
