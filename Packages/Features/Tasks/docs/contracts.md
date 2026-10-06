# Contracts

## Provides
- `TasksModule`: id `tasks`, tab, settings; `setEnabled` listens to the shortcut and loads the tasks.
- Its own shortcut `Hotkey.captureTask`.
- No Home widget and no notch indicator.

## Uses
- VortexCore: `FeatureModule`, `DataFolder`, `database`, design system (`SegmentedPicker`, `SettingsRow`, capsule buttons, `Hairline`).
- VortexPlatform:
  - `ScreenCaptureClient`: Screen Recording access; the display under the pointer, without Vortex's windows;
  - `FrontWindowClient`: the app in front, its window title, the page in a browser;
  - `TextRecognitionClient`: text on the pictures;
  - `ScreenOverlay`: the frozen screen above everything;
  - `FileClient`, `AppsClient` (`AppIcon`, open an app or a page in it), `QuickLookClient`, `NotificationClient`, `HotkeyClient`/`HotkeyRecorder`, `FileThumbnail`.
