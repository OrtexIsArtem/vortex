# Settings

| Setting | Default | Notes |
| --- | --- | --- |
| Lock the keyboard for cleaning | none | the shortcut that runs the utility action; stored by KeyboardShortcuts under `lockKeyboard`; the shell records it first on its page and listens for it while the utility runs |

- Its page in Settings › Features has no "open on its tab" shortcut: it has no tab.
- Accessibility off: a row "⚠ Accessibility · Locks the keyboard while you clean it." with "Turn on", which opens the shell's page.
- Accessibility granted for the next launch: the row reads "Works after restart" with "Restart Vortex", without yellow.
- Granted, not needed, or not read yet: no row.
- The page re-reads the statuses when it appears (`PermissionsClient.refresh`).
- A line under it says that the lock reads only which key goes down and keeps none of it.
