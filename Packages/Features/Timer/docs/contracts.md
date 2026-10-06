# Contracts

## Provides
- `TimerModule`: id `timer`, tab, settings; `setEnabled` resumes a saved run or ends the run.
- Home widget in the `header` slot: the drum and its minutes left of `notchCutout`, «+5» and Start (or pause and stop) right of it.
- Indicator `timer` in `@Shared(.notchIndicators)`, priority 10:
  - a ring (or a pause sign) and the time left;
  - no ears without a run;
  - an alarm when time is up and on Test, in the chosen color: the shell flashes the notch until the user sees it; a new run ends it.

## Uses
- VortexCore: `FeatureModule`, `HomeWidget`, `notchCutout`, `notchIndicators`, `ColorValue`, `DataFolder`, design system.
- VortexPlatform:
  - `SoundClient`: the system sounds;
  - `NotificationClient`: the notification with «+5 хв» and its button presses;
  - `ScrollDragArea`: scrolls, drags and clicks on the drum;
  - `ColorWell`.
