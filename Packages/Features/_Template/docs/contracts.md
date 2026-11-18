# Contracts

## Provides
- `TemplateModule` — the FeatureModule entry point for the registry: id, title, symbol, `makeTab()`.
- Optional, when needed: `makeSettings()`, `makeHomeWidgets()`, `acceptsFileDrops`, `setEnabled(_:)` to start and stop background work, `permissionNeeds` (each macOS permission with a one-line reason from this module's bundle), `makeOnboardingStep()` with `hasOnboardingStep`.
- The catalog's description, read without running the feature: `summary`, `details`, `author`; when they apply, `keeps`, `dataFolder`, `eraseNote`, `isBeta`, `preview` (media in `Sources/Resources/Catalog`, under 1.5 MB); `isRecommended` and `suspension` are the maintainer's.
- `eraseData()`, when the feature keeps something outside its tables, `<id>.json` and its folder, such as keychain items or its own shortcuts.
- Home widgets (`makeHomeWidgets()`): at most 2, ids `<id>.…`, each in 1–3 grid sizes (Small 1×1, Medium 2×1, Wide 4×1, Large 2×2, Full 4×2) or the notch row; the view reads its size from `homeWidgetSize`; a `#Preview` with `HomeWidgetPreview` per size, and a test that `HomeWidget.problems` finds none.

## Uses
- VortexCore: `FeatureModule`, design system; `@Shared(.notchIndicators)` to show something in the notch; `HomeWidget` and `HomeWidgetPreview`.
- VortexPlatform: nothing yet. Own shortcuts: `extension Hotkey` plus `HotkeyClient.presses`.
