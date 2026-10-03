# VortexCore

Shared ground for the shell and all features. Depends only on The Composable Architecture.

| File | What it covers |
| --- | --- |
| FeatureModule.swift | the contract every feature implements: id, title, symbol, tab, settings, accepting files, starting and stopping |
| NotchIndicator.swift | indicators for the closed notch, how they fill the ears, and the shared key `notchIndicators` features write to |
| AppPreferences.swift | theme and language values |
| DesignSystem/ | monochrome palette, window metrics, environment values (`notchCutout`, `isWindowOpen`), switch, capsule buttons, segmented picker, hairline |

Coming next: the SQLite database (stage 2), the Home widget contract (stage 3).
