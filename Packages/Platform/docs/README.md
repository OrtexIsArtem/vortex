# VortexPlatform

System clients and system-backed views; features reach the system only through them, so tests can substitute them. The notch window and the menu bar icon are not here: they belong to Shell.

| File | What it covers |
| --- | --- |
| Clients/HotkeyClient.swift | global shortcuts: a module declares its own `Hotkey`, listens with `presses`, shows `HotkeyRecorder` |
| Clients/PasteboardClient.swift | copies made in any app (checked twice a second), writing to the pasteboard, `AppInfo` |
| Clients/FileClient.swift | file info, reading, writing, copying, deleting, Show in Finder, folder picker, watching a folder |
| Clients/AppsClient.swift, FrontWindowClient.swift, QuickLookClient.swift | running apps, `AppIcon`, opening an app or a page in it; the app in front with its window title and browser page; the Quick Look panel, which Vortex windows hand over through `QuickLook` |
| Clients/LaunchAtLoginClient.swift, SystemClient.swift, SoundClient.swift, NotificationClient.swift | login item; theme, interface language, relaunch, quit; system sounds by name; notifications with buttons, shown even while Vortex is active (needs the app bundle, so not under `swift test`) |
| Clients/ScreenCaptureClient.swift, TextRecognitionClient.swift, Views/ScreenOverlay.swift | Screen Recording access and a display as it looks, without Vortex's windows (`Screenshot`, `ScreenImage`: crop, PNG, HEIC, read back decoded); text on images by Apple Vision, offline; a window over a whole display, above everything, that gives way when another app comes to the front: with Vortex brought to the front (`show`) or the app in front left as it is (`showKeepingFront`, which also keeps the shell's window open) |
| Views/DragSource.swift, DropTarget.swift, ScrollDragArea.swift, EditingShortcuts.swift | drags out (`DragSourceArea`: hover, clicks, several items; a press with nothing to drag stays a click) and in (`dropTarget`); scrolls and presses on a control such as the timer's drum (`ScrollDragArea`); the standard editing shortcuts for panels without a main menu, also under Cyrillic layouts (`EditingShortcuts`) |
| OutsideActivity.swift | whether a drag out, Quick Look, the folder picker or a picture over the whole display is in use, so the shell keeps the window open |
| Views/FileThumbnail.swift, ColorWell.swift | Quick Look thumbnails made in the background, `FileIcon`; a color picker whose panel floats above Vortex |
