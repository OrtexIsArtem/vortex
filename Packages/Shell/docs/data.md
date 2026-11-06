# Data

| What | Where | How long |
| --- | --- | --- |
| Shell settings and the last tab | DataFolder/settings.json (~/Library/Application Support/Vortex; a QA run's own folder in QA mode) | Until changed |
| Keyboard shortcuts | UserDefaults of the app, managed by KeyboardShortcuts | Until changed |
| Interface language | UserDefaults key AppleLanguages of the app — the only place it is kept | Until changed |
| First-launch login item setup done | UserDefaults key launchAtLoginSetUp, release builds only; set when Basics applies "Open at login" untouched; read to start Basics' switch from the real state | Forever |
| "Don't ask again" ticked with Not Now in the offer to move to /Applications | UserDefaults key moveToApplicationsDeclined, kept by Platform's AppInstallClient, release builds only | Forever |
| Onboarding progress: page, return to Done, pending checks, pending single page, completed, restarted, login item applied; the version that launched last (`version`, short version and build, "0.1.2 (17)") and, of Accessibility and Screen Recording, the permissions macOS ties to the signature, each one macOS reported granted with the version that saw it last (`granted`) | DataFolder/onboarding.json, written at once on every change | Until `onboarding reset` in QA; a missing file means a fresh onboarding |
| Permissions Vortex asked macOS for (notifications, Accessibility, Screen Recording) | ~/Library/Application Support/Vortex/permissions.json, kept by Platform's PermissionsClient | Forever |

- Missing, unknown or unreadable keys in settings.json fall back to their defaults; delays are clamped to 0–2 s.
- `version` is written after the launch's check for permissions an update dropped. A grant that reads `notGranted` under the version that saw it was turned off and is dropped; under a later version it stays, as granted before.
- An onboarding.json without `version` (0.1.1 and earlier) counts Accessibility and Screen Recording as granted then when permissions.json says Vortex asked for them, for that launch's check only: `granted` never keeps the guess, and a guess an earlier build kept is dropped at launch.
