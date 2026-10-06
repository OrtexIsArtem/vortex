# Behavior

## Setting the time
- The drum shows the minutes to start under a fixed mark: a tick per minute, a longer one every five; it turns from 1 to 120.
- Towards its edges the ticks crowd, shrink and fade, as on a drum seen from the front; in the Timer tab every fifth tick has its number.
- A mouse wheel turns it a minute per notch; two fingers on the trackpad, a minute per 6 pt (9 pt in the Timer tab), with momentum.
- The drum moves with the fingers or the pointer: a swipe or a drag to the left, or a swipe up, adds time.
- A drag keeps the window open, even past its edge; released outside it, the window waits 1.5 s for the pointer to come back before it may close.
- A click on a tick turns that tick to the mark; a press moved more than 2 pt either way is a drag, not a click.
- ← → in the Timer tab turn it a minute; VoiceOver can adjust it too.
- The drum stands at 5 minutes whenever it shows: it goes back there as the window opens, when its tab is shown again and when a run starts, whatever was set before.
- On Home «+5» and «+10» turn it on by that much, up to 120.

## Starting
- One timer at a time: Start (or Return in the Timer tab) starts a run of the minutes on the drum.
- The Timer tab has quick starts under Start: 5, 10, 15, 30 and 60 minutes, each starting at once.
- On Home the drum and its minutes stand left of the notch, «+5», «+10» and Start right of it.
- Without a notch (window under the menu bar icon) they stand in one row; short of room left of the notch, the drum narrows.

## While it runs
- The drum shows the time left, turning towards zero, and takes no input; beside it the time, e.g. 8:42.
- Start, the quick starts and «+5» «+10» give way to pause and stop.
- Pause keeps the time left; Resume goes on from there; Space pauses and resumes in the Timer tab.
- Stop ends the run without a sound.
- The Timer tab shows the time in large digits and «з 25 хв · до 14:57», paused «Пауза · з 25 хв».
- The closed notch shows a ring of the time left and the time; paused, a pause sign instead of the ring.
- Next to shelf files the timer takes the left ear.
- The time reads 25:00, 8:42, 0:05; an hour or more 1:05:00. It changes exactly at each whole second.

## When time is up
- The chosen sound plays once.
- A notification «Час вийшов» appears with a «+5 хв» button.
- The notch flashes, one flash after another, until the pointer comes or moves over it or the window opens; with the window open, three times.
- Starting a run, also with «+5 хв» on the notification, stops the flashes.
- «+5 хв» on the notification starts a five-minute run.
- The first run asks macOS once for permission to notify; without it everything else still happens.

## Lifetime
- A run goes on while the window is closed and after Vortex relaunches; one that ran out while Vortex was closed is dropped quietly.
- A run changed from outside (another Vortex, the run file edited or deleted) is followed at once: the notch shows it and it ticks, or stops.
- Turning the feature off ends the run and the flashes.
- Test in the settings plays the sound and starts the flashes three seconds later, without a notification.
