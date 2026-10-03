# VortexCore

Shared ground for the shell and all features. Depends only on The Composable Architecture.

| File | What it covers |
| --- | --- |
| FeatureModule.swift | the contract every feature implements: id, title, symbol, tab, settings, accepting files |
| NotchIndicator.swift | indicators for the closed notch, how they fill the ears, and `NotchIndicatorCenter` (dependency `notchIndicators`) |
| AppPreferences.swift | theme and language values |
| DesignSystem/ | monochrome palette, window metrics, toggle, primary capsule button, segmented picker, hairline |

Coming next: the Home widget contract (stage 3), the SQLite database (stage 2).
