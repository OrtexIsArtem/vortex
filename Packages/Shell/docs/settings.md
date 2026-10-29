# Settings

| Setting | Default | Notes |
| --- | --- | --- |
| Launch at login | on in release builds | System login item, not stored in settings.json |
| Language | system | System, Українська, English; needs a relaunch |
| Theme | system | System, light, dark |
| Open on hover | on | |
| Hover delay | 0.3 s | 0–2 s in 0.1 s steps |
| Open on click | on | |
| "Open Vortex" shortcut | none | Set by the user; stored by KeyboardShortcuts |
| A shortcut per feature tab | none | Listed for enabled features; stored by KeyboardShortcuts as `open-<feature id>` |
| Close on click outside | on | |
| Close when the pointer leaves | on | Only for a window opened by hover or by dragging files |
| Leave delay | 0.5 s | 0–2 s in 0.1 s steps |
| Menu bar icon | shown | Forced on while a display has no notch or the notch can't open Vortex |
| Feature order | registry order | Features missing from the saved order follow in registry order |
| Turned-off features | none | |
| Required permissions | none | `OnboardingConfig.requiredPermissions`, not in settings.json; QA mode may change them per run |
