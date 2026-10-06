# Contracts

## Provides
- `TimerModule`: id `timer`, tab, settings; `setEnabled` resumes a saved run or ends the run.
- Home widget in the `header` slot: presets or the run, laid out around `notchCutout`.
- Indicator `timer` in `@Shared(.notchIndicators)`, priority 10:
  - a ring (or a pause sign) and the time left;
  - no ears without a run;
  - three flashes in the chosen color when time is up.

## Uses
- VortexCore: `FeatureModule`, `HomeWidget`, `notchCutout`, `notchIndicators`, `ColorValue`, `DataFolder`, design system.
- VortexPlatform:
  - `SoundClient`: the system sounds;
  - `NotificationClient`: the notification with «+5 хв» and its button presses;
  - `ColorWell`.
