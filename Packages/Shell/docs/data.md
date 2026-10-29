# Data

| What | Where | How long |
| --- | --- | --- |
| Shell settings and the last tab | DataFolder/settings.json (~/Library/Application Support/Vortex; a QA run's own folder in QA mode) | Until changed |
| Keyboard shortcuts | UserDefaults of the app, managed by KeyboardShortcuts | Until changed |
| Interface language | UserDefaults key AppleLanguages of the app — the only place it is kept | Until changed |
| First-launch login item setup done | UserDefaults key launchAtLoginSetUp, release builds only | Forever |
| Permissions Vortex asked macOS for (notifications, Accessibility, Screen Recording) | ~/Library/Application Support/Vortex/permissions.json, kept by Platform's PermissionsClient | Forever |

- Missing, unknown or unreadable keys in settings.json fall back to their defaults; delays are clamped to 0–2 s.
