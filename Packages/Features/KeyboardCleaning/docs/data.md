# Data

Keyboard cleaning keeps nothing: no tables, no migrations, no `keyboard.json`, no folder.

| What | Where | How long |
| --- | --- | --- |
| Keys pressed during a lock: how often each place on the drawn keyboard went down, never what it types | In memory only; the live lock never writes, logs or sends them (a QA run logs the keys its commands simulate) | Until the lock ends |

- Its catalog page shows no "keeps" line and no Erase Data.
- The shortcut lives in KeyboardShortcuts' defaults and stays when the utility is removed, so adding it again keeps it.
- The first launch of the build that made it a utility keeps it added for whoever had Vortex before (the shell's `keyboard.added` migration, settings.json).
