# Contracts

## Provides
- `ShelfModule` — id `shelf`, tab, `acceptsFileDrops`, `receiveFiles(_:)`, `setEnabled(_:)` starts and stops expiry.
- `@Shared(.notchIndicators)["shelf"]`: tray and the number of files that came by themselves and still have their dot (no ears while there are none, whatever else is on the shelf), flashing in a color when such files arrive.
- Home widget in the `dock` slot.

## Uses
- VortexCore: `FeatureModule`, `@Dependency(\.database)`, `databaseIsOnDisk` with its own migrator (`shelf.v1`), `DataFolder`, design system, `Text(age:now:)`.
- VortexPlatform: `ColorWell` (flash colors), `dropTarget` (drops from other apps), `DragSourceArea` (dragging out), `FileClient` (info, copies, open, Show in Finder, folder picker, `changes` of the watched folder), `QuickLookClient`, `FileThumbnail`, `FileIcon`.
- The shell gives it files dropped on the menu bar icon (none on macOS 26, where the drop never reaches Vortex) and opened with Vortex; Tools/CLI/vortex opens files with Vortex.
