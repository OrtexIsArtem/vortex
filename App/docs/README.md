# App

Entry point only: main.swift starts AppKit with AppDelegate, which starts `ShellController` from VortexShell. No Dock icon (LSUIElement). Target settings (bundle id, signing, Info.plist keys) live in project.yml.

Debug builds can be driven by scripts without touching the pointer, through distributed notifications:
- `io.github.ortexisartem.vortex.debug.toggle` — open or close the window, as the shortcut does;
- `io.github.ortexisartem.vortex.debug.indicator` — show or hide a test indicator in the notch.
