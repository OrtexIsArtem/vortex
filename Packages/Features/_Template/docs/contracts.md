# Contracts

## Provides
- `TemplateModule` — the FeatureModule entry point for the registry: id, title, symbol, `makeTab()`.
- Optional, when needed: `makeSettings()`, `makeHomeWidget()`, `acceptsFileDrops`, `setEnabled(_:)` to start and stop background work, `permissionNeeds` (each macOS permission with a one-line reason from this module's bundle), `makeOnboardingStep()` with `hasOnboardingStep`.
- The catalog's description, read without running the feature: `summary`, `details`, `author`; when they apply, `keeps`, `dataFolder`, `eraseNote`, `isBeta`, `preview` (media in `Sources/Resources/Catalog`, under 1.5 MB); `isRecommended` and `suspension` are the maintainer's.
- `eraseData()`, when the feature keeps something outside its tables, `<id>.json` and its folder, such as keychain items or its own shortcuts.

## Uses
- VortexCore: `FeatureModule`, design system; `@Shared(.notchIndicators)` to show something in the notch.
- VortexPlatform: nothing yet. Own shortcuts: `extension Hotkey` plus `HotkeyClient.presses`.
