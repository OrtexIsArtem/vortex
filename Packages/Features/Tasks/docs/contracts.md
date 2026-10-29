# Contracts

## Provides
- `TasksModule`: id `tasks`, tab, settings; `setEnabled` listens to the shortcut and loads the tasks.
- Its own shortcut `Hotkey.captureTask`.
- No Home widget and no notch indicator. While a capture or a task's whole screen covers the display it draws its own notch pill over the real notch.
- `permissionNeeds`: Screen Recording, «Робить задачу зі знімка екрана.»
- Debug builds outside QA mode: distributed notifications `…debug.task*` drive a capture and the list (see TasksModule); a QA run (VortexPlatform's `QA`) listens to none.

## Uses
- VortexCore: `FeatureModule`, `DataFolder`, `database`, `databaseIsOnDisk`, design system (`SegmentedPicker`, `SettingsRow`, `PermissionRows`, `WarningMark`, capsule buttons, `Hairline`).
- VortexCore permissions: `@SharedReader(.permissionStatuses)` and `@SharedReader(.appBlocked)`, written by the shell; `permissionPage.open(.screenRecording)` instead of asking macOS.
- VortexPlatform:
  - `PermissionsClient`: `refresh()` when the settings section appears;
  - `SystemClient.relaunch`: "Restart Vortex" in the settings row;
  - `ScreenCaptureClient`: the display under the pointer, without Vortex's windows;
  - `FrontWindowClient`: the app in front, its window title, the page in a browser;
  - `TextRecognitionClient`: text on the pictures;
  - `ScreenOverlay`: the frozen screen above everything, with the standard editing shortcuts (`EditingShortcuts`); a task's whole screen with `showKeepingFront`;
  - `ScreenImage`: the pictures, cropped, encoded and read back decoded;
  - `FileClient`, `AppsClient` (`AppIcon`, open an app or a page in it), `HotkeyClient`/`HotkeyRecorder`, `FileThumbnail`.
