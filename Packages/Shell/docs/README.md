# Shell

The app shell: the notch window and the menu bar icon, opening and closing, the sidebar, the shell settings.

| File | What it covers |
| --- | --- |
| behavior.md | when the window opens and closes, which tab it shows, keyboard cleaning, permission statuses and blocking |
| settings.md | shell settings and their defaults |
| data.md | where the settings live, what Vortex asked macOS for |
| contracts.md | what the shell gives the app and takes from features, Core and Platform |

Code: ShellFeature.swift (logic, tested), ShellController.swift (start-up, menu), FeaturesClient.swift,
Window/ (panels, chrome, ears, menu bar icon — AppKit, reports events to ShellFeature), Views/, Settings/,
KeyboardCleaning/ (the mode's reducer and screen, scoped into ShellFeature; tested), Permissions/ (what is needed and required; tested).
