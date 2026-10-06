# VortexPlatform

System clients and system-backed views; features reach the system only through them, so tests can substitute them. The notch window and the menu bar icon are not here: they belong to Shell.

| File | What it covers |
| --- | --- |
| Clients/HotkeyClient.swift | global shortcuts: a module declares its own `Hotkey`, listens with `presses`, shows `HotkeyRecorder` |
| Clients/LaunchAtLoginClient.swift, SystemClient.swift | login item; theme, interface language, relaunch, quit |
| Clients/PasteboardClient.swift | copies made in any app (checked twice a second), writing to the pasteboard, `AppInfo` |
| Clients/FileClient.swift | file info, reading, writing, copying, deleting, Show in Finder, folder picker, watching a folder |
| Clients/AppsClient.swift, QuickLookClient.swift | running apps and `AppIcon`; the Quick Look panel, which Vortex windows hand over through `QuickLook` |
| Clients/SoundClient.swift, NotificationClient.swift | system sounds by name; notifications with buttons, shown even while Vortex is active (needs the app bundle, so not under `swift test`) |
| Views/DragSource.swift, DropTarget.swift, ScrollDragArea.swift | drags out (`DragSourceArea`: hover, clicks, several items; a press with nothing to drag stays a click) and in (`dropTarget`); scrolls and presses on a control such as the timer's drum (`ScrollDragArea`) |
| OutsideActivity.swift | whether a drag out, Quick Look or the folder picker is in use, so the shell keeps the window open |
| Views/FileThumbnail.swift, ColorWell.swift | Quick Look thumbnails made in the background, `FileIcon`; a color picker whose panel floats above Vortex |
