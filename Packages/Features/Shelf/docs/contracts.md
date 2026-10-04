# Contracts

## Provides
- `ShelfModule` — id `shelf`, tab, `acceptsFileDrops`, `receiveFiles(_:)`, `setEnabled(_:)` starts and stops expiry.
- `@Shared(.notchIndicators)["shelf"]`: tray and count, flashing when files arrive by themselves.

## Uses
- VortexCore: `FeatureModule`, `@Dependency(\.database)` with its own migrator (`shelf.v1`), `DataFolder`, design system, `Text(age:now:)`.
- VortexPlatform: `dropTarget` (drops from other apps), `DragSourceArea` (dragging out), `FileClient` (info, copies, open, Show in Finder), `QuickLookClient`, `FileThumbnail`, `FileIcon`.
- The shell gives it files dropped on the menu bar icon and opened with Vortex.

## Not yet
- The watched folder and `vortex shelf add` (stage 2, step 3); the Home widget and drags between the shelf and the clipboard (stage 3).
