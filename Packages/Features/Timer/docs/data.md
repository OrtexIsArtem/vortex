# Data

No database tables.

| What | Where | How long |
| --- | --- | --- |
| Settings | DataFolder/timer.json | until changed |
| The run going: its end (or the time left while paused) and its total | DataFolder/Timer/run.json | until it is stopped or runs out; an unreadable file counts as no run |

- A run file with impossible values (a total over 24 hours, a time left above the total, an end date far off) counts as no run.
