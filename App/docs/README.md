# App

Entry point only: main.swift starts AppKit with AppDelegate, which creates `ShellController` from VortexShell, starts it, hands it files opened with Vortex (`vortex shelf add`, `open -a Vortex`) and asks it to save settings when the app quits. A Vortex started while another runs (a build from Xcode next to one opened before) asks the other to quit, which saves its settings, and stops it after 2 s if it is still there: one instance owns the data, the notch and the MCP port. No Dock icon (LSUIElement). Target settings (bundle id, signing, Info.plist keys, the en/uk localizations) live in project.yml.

Debug builds can be driven by scripts without touching the pointer, through distributed notifications:
- `io.github.ortexisartem.vortex.debug.toggle` — open or close the window, as the shortcut does;
- `io.github.ortexisartem.vortex.debug.indicator` — show or hide a test indicator in the notch;
- `io.github.ortexisartem.vortex.debug.permissions` — ask now for Screen Recording and Automation of the running browsers;
- `io.github.ortexisartem.vortex.debug.tab` — switch to a tab (userInfo `id`; `settings` takes a `section`);
- features add their own: Tasks drives a capture with `…taskCapture`, `…taskCaptureImage`, `…taskFrame`, `…taskSave` and more, listed in TasksModule.

Target settings also give the app the Apple Events entitlement and its usage text, for the page addresses of browsers.
