# Contracts

## Provides
- `ClipboardModule` — id `clipboard`, tab, settings section, `setEnabled(_:)` starts and stops recording.
- Home widget in the `dock` slot.
- `permissionNeeds`: Paste from Other Apps, "Keeps your clipboard history." It shows only where macOS enforces pasteboard privacy and asks or denies: on macOS 26.4 it reads `notNeeded`, as do apps macOS never asked (`.default`); revisit on macOS 27.

## Uses
- VortexCore: `FeatureModule`, `@Dependency(\.database)`, `databaseIsOnDisk` with its own migrator (`clipboard.v1`, `clipboard.v2`), `DataFolder`, design system, `SettingsRow`, `PermissionRows`; `@SharedReader(.permissionStatuses)` (the row, and recording nothing while Paste from Other Apps reads `notGranted`) and `permissionPage.open`.
- VortexPlatform permissions: `PermissionsClient.refresh` when the settings section appears, `SystemClient.relaunch` for "Restart Vortex".
- VortexPlatform: `PasteboardClient` (copies and writing), `FileClient` (image files and their sizes, missing files, Show in Finder), `TextRecognitionClient.recognizeForSearch` (the text on a new image, for search), `FileName` (the names search looks through), `AppsClient` and `AppIcon` (sources, ignored apps), `DragSourceArea` (dragging cards and rows out), `dropTarget` (drops on the Home widget), `FileThumbnail`, `FileIcon`.

## Not yet
- "Make key" for Secrets; "Paste right away".
