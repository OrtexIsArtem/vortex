# Contracts

## Provides
- `UtilityTemplateModule`: id `utilitytemplate`, a utility (`UtilityModule`): no tab, no `makeTab()`; its kind comes from that type.
- One utility action, `utilitytemplate.hello` ("Say Hello", help "Say hello in the notch", `hand.wave`): window `.closed`, no permission, shortcut `sayHello`; it sends `sayHello`.
- Its notch indicator `utilitytemplate`, while the hello shows.
- Optional, when needed: `makeSettings()` (on its page in Settings › Features, after the shortcut the shell shows), `makeWindowCover()` with `@Shared(.windowCover)` for a screen over the whole window (its action then needs the window `.open`), `permissionNeeds`, `setEnabled(_:)`, `makeOnboardingStep()` with `hasOnboardingStep`.
- The catalog's description: `summary`, `details`, `author`; `keeps`, `dataFolder`, `eraseNote`, `isBeta` and `preview` when they apply.

## Uses
- VortexCore: `UtilityModule`, `UtilityAction`, `@Shared(.notchIndicators)`.
- VortexPlatform: `Hotkey`, its own shortcut, which the shell records and listens for.
