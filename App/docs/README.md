# App

Entry point only: main.swift starts AppKit with AppDelegate, which creates `ShellController` from VortexShell, starts it, hands it files opened with Vortex (`vortex shelf add`, `open -a Vortex`) and asks it to save settings when the app quits. No Dock icon (LSUIElement). Target settings (bundle id, signing, Info.plist keys, the en/uk localizations) live in project.yml.

Debug builds can be driven by scripts without touching the pointer, through distributed notifications:
- `io.github.ortexisartem.vortex.debug.toggle` — open or close the window, as the shortcut does;
- `io.github.ortexisartem.vortex.debug.indicator` — show or hide a test indicator in the notch.
