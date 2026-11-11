# Settings

| Setting | Default | Notes |
| --- | --- | --- |
| Keep history | A month | A week, A month, 3 months, A year, Forever: how long an unpinned item stays after its last copy |
| Ignored apps | none | Added from the running apps (menu bar apps too) or any app chosen with Other…; nothing copied in them is recorded |

- Keep history is stored in clipboard.json as `historyLifetime` (`week`, `month`, `threeMonths`, `year`, `forever`).
- A missing or unknown value reads as `month`.
- Its caption: "Pinned items stay. The history holds at most 10,000 items and 1 GB; past that the oldest pictures go first."
- What a choice removes, and its Undo, are in history.md.
- The row "History" shows "1,234 items · 312 MB": every item, pinned ones too; a secret takes 0 bytes.
- Its Clear works as the tab's.
- The row hides while the history is empty; its Clear hides while nothing is unpinned.
- The Undo toast of Clear or a shorter Keep history shows under these rows for 5 s.
- Paste from Other Apps off (macOS enforces pasteboard privacy and Vortex isn't allowed) shows a row "⚠ Paste from Other Apps · Keeps your clipboard history.".
- Its "Turn on" opens the shell's page.
- ↻ shows "Works after restart" with "Restart Vortex".
- `notNeeded` (macOS 26.4) shows no row.
- The section re-reads the statuses when it appears (`PermissionsClient.refresh`).
