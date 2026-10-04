# VortexPlatform

System clients and system-backed views; features reach the system only through them, so tests can substitute them.

| File | What it covers |
| --- | --- |
| Clients/HotkeyClient.swift | global shortcuts: a module declares its own `Hotkey`, listens with `presses`, shows `HotkeyRecorder` |
| Clients/LaunchAtLoginClient.swift, SystemClient.swift | login item; theme, interface language, relaunch, quit |
| Clients/PasteboardClient.swift | copies made in any app (checked twice a second), writing to the pasteboard, `AppInfo` |
| Clients/FileClient.swift | file info, reading, writing, copying, deleting, Show in Finder, folder picker, watching a folder |
| Clients/AppsClient.swift, QuickLookClient.swift | running apps and `AppIcon`; the Quick Look panel, which Vortex windows hand over through `QuickLook` |
| Views/DragSource.swift | `DragSourceArea`: hover, clicks and multi-item drags out of Vortex; `DragSessions` says when one runs |
| Views/FileThumbnail.swift | Quick Look thumbnails made in the background, `FileIcon` |

Not here: the notch window and the menu bar icon (Shell). Planned: screen capture (stage 4), Keychain (stage 5).
