# Contracts

## Provides
- `ClipboardModule` — id `clipboard`, tab, settings section, `setEnabled(_:)` starts and stops recording.
- Home widget in the `dock` slot.

## Uses
- VortexCore: `FeatureModule`, `@Dependency(\.database)`, `databaseIsOnDisk` with its own migrator (`clipboard.v1`), `DataFolder`, design system, `SettingsRow`.
- VortexPlatform: `PasteboardClient` (copies and writing), `FileClient` (image files, missing files, Show in Finder), `AppsClient` and `AppIcon` (sources, ignored apps), `DragSourceArea` (dragging cards and rows out), `dropTarget` (drops on the Home widget), `FileThumbnail`, `FileIcon`.

## Not yet
- "Make key" for Secrets (stage 5); "Paste right away" (stage 6).
