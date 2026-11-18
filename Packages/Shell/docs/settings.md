# Settings

| Setting | Default | Notes |
| --- | --- | --- |
| Open at login | on once Basics is left, on a fresh install | System login item, not stored in settings.json; Basics shows it on (an install that set it up before: the real state) and applies the user's choice on leaving, in release builds |
| Language | system | System, Українська, English; needs a relaunch |
| Theme | system | System, light, dark |
| Open on hover | on | |
| Hover delay | 0.3 s | 0–2 s in 0.1 s steps |
| Open on click | on | |
| "Open Vortex" shortcut | none | Set by the user; stored by KeyboardShortcuts |
| A shortcut per feature tab | none | First on the feature's page in Settings › Features; stored by KeyboardShortcuts as `open-<feature id>`, listened for only while the feature runs |
| Close on click outside | on | |
| Close when the pointer leaves | on | Only for a window opened by hover or by dragging files |
| Leave delay | 0.5 s | 0–2 s in 0.1 s steps |
| Menu bar icon | shown | Forced on while a display has no notch or the notch can't open Vortex |
| Feature order | registry order | Features missing from the saved order follow in registry order |
| Added features (`addedFeatures`) | fresh install: the recommended and built-in ones; an update from before the catalog: every feature but the turned-off ones | Built-in ones are always added; ids of features this build lacks are kept |
| Features chosen (`featuresChosen`) | false on a fresh install, true otherwise | Until true only built-in features run; set by leaving the onboarding's Features page or closing the onboarding |
| Seen features (`seenFeatures`) | every feature at the first launch with the catalog | One missing is New in the catalog |
| Stopped features (`stoppedFeatures`, `stoppedInVersion`) | none | Stopped after a crash until Try Again; another build forgets them |
| Features to erase (`pendingErase`) | none | Erased at the next launch, before anything starts |
| `disabledFeatures` | — | Read once from settings written before the catalog to fill the added features; empty afterwards |
| Required permissions | none | `OnboardingConfig.requiredPermissions`, not in settings.json; QA mode may change them per run |
