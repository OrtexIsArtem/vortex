# Settings

DataFolder/timer.json; unreadable keys fall back to their defaults.

| Setting | Default | Notes |
| --- | --- | --- |
| Sound | Glass | a system sound or none; choosing one plays it |
| Notch flash | warm orange #FF9F43 | the color the notch flashes in when time is up, until the pointer comes over it; Test plays it |

The drum's minutes are not kept: it stands at 5 whenever it shows. Older files may hold `presets` and `lastMinutes`; they are ignored and dropped at the next save.
