# Data

| What | Where | How long |
| --- | --- | --- |
| Shell settings and the last tab | DataFolder/settings.json (~/Library/Application Support/Vortex; a QA run's own folder in QA mode) | Until changed |
| Keyboard shortcuts | UserDefaults of the app, managed by KeyboardShortcuts | Until changed |
| Interface language | UserDefaults key AppleLanguages of the app — the only place it is kept | Until changed |
| First-launch login item setup done | UserDefaults key launchAtLoginSetUp, release builds only; set when Basics applies "Open at login" | Forever |
| Onboarding progress: page, return to Done, pending checks, pending single page, completed, restarted, login item applied | DataFolder/onboarding.json, written at once on every change | Until `onboarding reset` in QA; a missing file means a fresh onboarding |
| Permissions Vortex asked macOS for (notifications, Accessibility, Screen Recording) | ~/Library/Application Support/Vortex/permissions.json, kept by Platform's PermissionsClient | Forever |

- Missing, unknown or unreadable keys in settings.json fall back to their defaults; delays are clamped to 0–2 s.
