# Data

| What | Where | How long |
| --- | --- | --- |
| Shell settings and the last tab | ~/Library/Application Support/Vortex/settings.json | Until changed |
| Keyboard shortcuts | UserDefaults of the app, managed by KeyboardShortcuts | Until changed |
| Language override | UserDefaults key AppleLanguages of the app | Until changed |

- Missing, unknown or unreadable keys in settings.json fall back to their defaults; delays are clamped to 0–2 s.
