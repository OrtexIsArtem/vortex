# VortexPlatform

System clients for the shell and features. Features reach the system only through these, so tests can substitute them.

| File | What it covers |
| --- | --- |
| Clients/HotkeyClient.swift | global shortcuts: a module declares its own `Hotkey`, listens with `presses`, shows `HotkeyRecorder` in its settings |
| Clients/LaunchAtLoginClient.swift | login item status, turning it on and off, the first-launch setup of release builds |
| Clients/SystemClient.swift | theme, interface language, relaunch, quit |

The notch window and the menu bar icon belong to the shell (Packages/Shell/Sources/Window); features show status there through `@Shared(.notchIndicators)` in Core.
Planned: pasteboard and file watcher (stage 2), screen capture and window info (stage 4), Keychain (stage 5).
