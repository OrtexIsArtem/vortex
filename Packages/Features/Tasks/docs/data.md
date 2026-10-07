# Data

Tables are created by the feature's migrator (`tasks.v1`, `tasks.v2`) before its first query.

| What | Where | How long |
| --- | --- | --- |
| A task: number, title, priority, when taken and done, source (app, window title, page address), the part's size and place on the screen, the screen's size, recognized text | table `tasks_task`, one row per task | until deleted, or 30 days after it was done |
| The last number given | table `tasks_counter` | always |
| The framed part, PNG | DataFolder/Tasks/<id>/crop.png | with its task |
| The whole screen, HEIC | DataFolder/Tasks/<id>/screen.heic | with its task |
| Whether the Screen Recording prompt was shown | DataFolder/tasks.json | always |

- Numbers are never given twice: the next is one more than the highest ever given, also after that task is deleted.
- If another Vortex took the number a capture showed, it saves with the next one, and an untouched «Задача N» title follows.
- The pictures are written before the row, so a row always has them; at launch, picture folders without a row are deleted.
- A deleted task's row goes at once, its pictures once the deletion can't be taken back (5 s, or the next change that can be); taken back, the row is written again as it was. If Vortex quits meanwhile, the deletion stands.
- Rows this version can't read (written by a newer Vortex) are skipped and kept.
- Recognized text is empty until recognition has run; empty text means none was found.
- The part's place and the screen's size are in points; tasks saved before `tasks.v2` have none, and the whole screen shows them undimmed.
- The whole screen is saved as taken; the dimming around the part is only drawn when it is shown.
- A change in the card writes only its own column (title, priority, done), never the whole row.
