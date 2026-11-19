# Contracts

## Provides
- `ClipboardModule` — id `clipboard`, tab, settings section, `setEnabled(_:)` starts and stops recording.
- The catalog's description: one line, details, author; Recommended; it keeps its history and pinned items in the table `clipboard_item` and the folder Clipboard/, which Erase Data deletes (no own erase hook).
- Home widget `clipboard.history` ("History") on the grid: Large 2×2 first, the size Home's first layout gives it, then Medium 2×1.
- `permissionNeeds`: Paste from Other Apps, "Keeps your clipboard history." It shows only where macOS enforces pasteboard privacy and asks or denies: on macOS 26.4 it reads `notNeeded`, as do apps macOS never asked (`.default`); revisit on macOS 27.

## Uses
- VortexCore: `FeatureModule`, `@Dependency(\.database)`, `databaseIsOnDisk` with its own migrator (`clipboard.v1`, `clipboard.v2`), `DataFolder`, design system, `SettingsRow`, `PermissionRows`; `@SharedReader(.permissionStatuses)` (the row, and recording nothing while Paste from Other Apps reads `notGranted`) and `permissionPage.open`.
- VortexPlatform permissions: `PermissionsClient.refresh` when the settings section appears, `SystemClient.relaunch` for "Restart Vortex".
- VortexPlatform: `PasteboardClient` (copies and writing), `FileClient` (image files and their sizes, missing files, Show in Finder, the texts Quick Look shows), `QuickLookClient` (an item in Quick Look, which keeps the shell's window open while it shows), `TextRecognitionClient.recognizeForSearch` (the text on a new image, for search), `FileName` (the names search looks through), `AppsClient` and `AppIcon` (sources, ignored apps), `DragSourceArea` (dragging cards and rows out), `dropTarget` (drops on the Home widget), `FileThumbnail`, `FileIcon`.

## Not yet
- "Make key" for Secrets; "Paste right away".
