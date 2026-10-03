# VortexPlatform

System clients. The shell and features reach the system only through these, so tests can substitute them.

| File | What it covers |
| --- | --- |
| Windowing/WindowController.swift | the closed notch with ears, the window that grows from the notch or drops under the menu bar icon, the icon itself; reports `WindowEvent` |
| Windowing/WindowChromeView.swift | the window outline and its open/close animation, simplified with Reduce Motion |
| Windowing/NotchEarsView.swift | indicators around the notch and their measured width |
| Windowing/Panels.swift | borderless panels above the menu bar; hover, click and file-drag detection |
| Geometry/ScreenGeometry.swift | notch and window frames, pure math (tested) |
| Clients/ | WindowClient, HotkeyClient (KeyboardShortcuts), LaunchAtLoginClient (SMAppService), SystemClient (theme, language, relaunch, quit) |

- Hover and leaving use tracking areas; the click-outside monitor exists only while the window is open. Nothing polls.
- Panels never activate the app; the window becomes key so Esc and text fields work.
- Planned: pasteboard and file watcher (stage 2), screen capture and window info (stage 4), Keychain (stage 5).
