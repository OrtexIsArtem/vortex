# Contracts

## Provides
- `ScreenTextModule`: id `screentext`, no tab (`hasTab` false), settings; `setEnabled` starts and stops the feature.
- The catalog's description: one line, details, author; not recommended; keeps nothing; media in Resources/Catalog, a temporary placeholder (the symbol, the name and "Preview coming soon") until the real clip is recorded.
- One utility action, `screentext.copy` ("Copy Text", help "Copy text from the screen", `text.viewfinder`): window `.closed`, permission Screen Recording, shortcut `copyScreenText`; it sends `captureRequested`.
- Its own shortcut `Hotkey.copyScreenText`, recorded on its settings page; the shell listens for it, through the utility action.
- Its notch indicator `screentext`, priority 15, while a message shows: its words as text items.
- `permissionNeeds`: Screen Recording, "Reads the text in a frame you draw on the screen."
- QA mode (debug builds, ScreenTextQA.swift): the command `screentext capture|drag|frame x= y= w= h=|release|cancel|fixture [background=]|press=turnOn|restart`, the state section `screentext` and the windows `screentext` (the frozen screen) and `screentext-settings`.

## Uses
- VortexCore: `FeatureModule`, `UtilityAction`, `@Shared(.notchIndicators)`, `@SharedReader(.permissionStatuses)` and `@SharedReader(.appBlocked)`, `permissionPage.open(.screenRecording)` instead of asking macOS, design system (`SettingsRow`, `PermissionRows`).
- VortexPlatform:
  - `ActiveAppClient.frontmost`: the app the text comes from;
  - `ScreenCaptureClient`: the display under the pointer, refused while another frozen screen shows;
  - `ScreenOverlay`: the frozen screen above everything, one at a time (`FrozenScreen`);
  - `TextRecognitionClient`: `readQRCode`, then `recognize`;
  - `PasteboardClient.copy`: a copy of the user's own, which Clipboard keeps, concealed for a secret;
  - `PermissionsClient.refresh`, `SystemClient.relaunch`, `HotkeyRecorder`.
