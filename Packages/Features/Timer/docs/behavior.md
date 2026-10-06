# Behavior

## Starting
- One timer at a time: while a run is going, the presets give way to its controls.
- A preset on Home starts a run at once.
- In the Timer tab, ‹ › (or ← →) pick a preset and Start (or Return) starts it.
- The preset started last is marked with ▶ on Home, and the Timer tab opens on it; "+5 min" on a notification does not change it.
- On Home the presets stand next to the notch, half on each side; while a run goes there: «з 25 хв», the ring, the time, pause, stop and «+5 хв».
- Without a notch (window under the menu bar icon) they stand in one row.
- When the presets left of the notch do not fit, the ⏱ icon goes first; the numbers on the chips never wrap.

## While it runs
- Pause keeps the time left; Resume goes on from there; Space pauses and resumes in the Timer tab.
- +5 min adds five minutes to the time left and to the total, running or paused.
- Stop ends the run without a sound.
- The closed notch shows a ring of the time left and the time, e.g. 8:42; paused, a pause sign instead of the ring.
- Next to shelf files the timer takes the left ear.
- The time reads 25:00, 8:42, 0:05; an hour or more 1:05:00. It changes exactly at each whole second.

## When time is up
- The chosen sound plays.
- A notification «Час вийшов» appears with a «+5 хв» button.
- The notch flashes three times, 1.5 s apart.
- «+5 хв» on the notification starts a five-minute run.
- The first run asks macOS once for permission to notify; without it everything else still happens.

## Lifetime
- A run goes on while the window is closed and after Vortex relaunches; one that ran out while Vortex was closed is dropped quietly.
- A run changed from outside (another Vortex, the run file edited or deleted) is followed at once: the notch shows it and it ticks, or stops.
- Turning the feature off ends the run.
- Test in the settings plays the sound and the flashes three seconds later, without a notification.
