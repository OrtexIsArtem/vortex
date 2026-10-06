# Data

Tables are created by the feature's migrator (`tasks.v1`) before its first query.

| What | Where | How long |
| --- | --- | --- |
| A task: number, title, priority, when taken and done, source (app, window title, page address), the part's size, recognized text | table `tasks_task`, one row per task | until deleted, or 30 days after it was done |
| The last number given | table `tasks_counter` | always |
| The framed part, PNG | DataFolder/Tasks/<id>/crop.png | with its task |
| The whole screen, HEIC | DataFolder/Tasks/<id>/screen.heic | with its task |

- Numbers are never given twice: the next is one more than the highest ever given, also after that task is deleted.
- If another Vortex took the number a capture showed, it saves with the next one, and an untouched «Задача N» title follows.
- The pictures are written before the row, so a row always has them; at launch, picture folders without a row are deleted.
- Rows this version can't read (written by a newer Vortex) are skipped and kept.
- Recognized text is empty until recognition has run; empty text means none was found.
