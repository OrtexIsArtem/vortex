# Contracts

## Provides
- `TimerModule`: id `timer`, tab, settings; `setEnabled` resumes a saved run or ends the run.
- Home widget in the `header` slot: the drum and its minutes left of `notchCutout`, «+5», «+10» and Start (or pause and stop) right of it.
- Indicator `timer` in `@Shared(.notchIndicators)`, priority 10:
  - a ring (or a pause sign) and the time left;
  - no ears without a run;
  - an alarm when time is up and on Test, in the chosen color: the shell flashes the notch until the user sees it; a new run ends it.
- `permissionNeeds`: notifications, «Повідомляє, коли таймер закінчився.»

## Uses
- VortexCore: `FeatureModule`, `HomeWidget`, `notchCutout`, `notchIndicators`, `ColorValue`, `DataFolder`, design system (`PermissionRows`); `@SharedReader(.permissionStatuses)` and `permissionPage.open` for the Notifications row.
- VortexPlatform: `PermissionsClient.refresh` when the settings section appears, `SystemClient.relaunch` for "Restart Vortex".
- VortexPlatform:
  - `SoundClient`: the system sounds;
  - `NotificationClient`: the notification with «+5 хв» and its button presses;
  - `ScrollDragArea`: scrolls, drags and clicks on the drum;
  - `ColorWell`.
- SwiftUI `sensoryFeedback(.alignment)`: the drum's ticks; macOS plays them only to a finger on a Force Touch trackpad, with «Force Click and haptic feedback» on.
