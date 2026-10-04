# Contracts

## Provides
- `ClipboardModule` — id `clipboard`, tab, settings section, `setEnabled(_:)` starts and stops recording.

## Uses
- VortexCore: `FeatureModule`, `@Dependency(\.database)` with its own migrator (`clipboard.v1`), `DataFolder`, design system, `SettingsRow`.
- VortexPlatform: `PasteboardClient` (copies and writing), `FileClient` (image files, missing files, Show in Finder), `AppsClient` and `AppIcon` (sources, ignored apps), `DragSourceArea` (dragging cards out), `FileThumbnail`, `FileIcon`.

## Not yet
- "Make key" for Secrets (stage 5); "Paste right away" (stage 6); dropping things onto the history and the Home widget (stage 3).
