# Settings

DataFolder/timer.json; unreadable keys fall back to their defaults.

| Setting | Default | Notes |
| --- | --- | --- |
| Sound | Glass | a system sound or none; choosing one plays it. Stored by file name, shown and sorted by the name System Settings › Sound gives it in macOS 26, in the app's language (Glass is Crystal); a sound without one shows its file name (SoundName.swift) |
| Notch flash | warm orange #FF9F43 | the color the notch flashes in when time is up, until the pointer comes over it; Test plays it |

The drum's minutes are not kept: it stands at 5 whenever it shows. Older files may hold `presets` and `lastMinutes`; they are ignored and dropped at the next save.

- Notifications off: a row "⚠ Notifications · Tells you when a timer ends." with "Turn on", which opens the shell's page; granted for the next launch: "Works after restart" with "Restart Vortex", without yellow; otherwise no row.
- The section re-reads the statuses when it appears (`PermissionsClient.refresh`).
