# Data

No database tables.

| What | Where | How long |
| --- | --- | --- |
| Settings | DataFolder/timer.json | until changed |
| The run going: its end (or the time left while paused) and its total | DataFolder/Timer/run.json | until it is stopped or runs out; an unreadable file counts as no run |

- The run file is written right after each change (start, pause, resume, +5, stop, time up), so a quit or a crash right after one loses nothing.
- A run file with impossible values (a total over 24 hours, a time left above the total) counts as no run.
- The end date of a running run is not limited: the time left is never counted below zero or above the total, so an end far off is a run with all its time left and one long gone is over.
