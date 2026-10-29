# App

Entry point only: main.swift starts AppKit with AppDelegate, which creates `ShellController` from VortexShell, starts it, hands it files opened with Vortex (`vortex shelf add`, `open -a Vortex`) and asks it to save settings when the app quits. A Vortex started while another runs (a build from Xcode next to one opened before) asks the other to quit, which saves its settings, and stops it after 2 s if it is still there: one instance owns the data, the notch and the MCP port. Of two started at about the same moment, the later one stays. A QA run takes over only from the same run, and plain Vortex only from plain Vortex. No Dock icon (LSUIElement). Target settings (bundle id, signing, Info.plist keys, the en/uk localizations) live in project.yml.

Debug builds outside QA mode can be driven by scripts without touching the pointer, through distributed notifications:
- `io.github.ortexisartem.vortex.debug.toggle` — open or close the window, as the shortcut does;
- `io.github.ortexisartem.vortex.debug.indicator` — show or hide a test indicator in the notch;
- `io.github.ortexisartem.vortex.debug.permissions` — ask now for Screen Recording and Automation of the running browsers;
- `io.github.ortexisartem.vortex.debug.tab` — switch to a tab (userInfo `id`; `settings` takes a `section`);
- features add their own: Tasks drives a capture with `…taskCapture`, `…taskCaptureImage`, `…taskFrame`, `…taskSave` and more, listed in TasksModule.

Target settings also give the app the Apple Events entitlement and its usage text, for the page addresses of browsers.

## QA mode
A debug build started with `--qa <name>` (1–16 letters, digits or dashes) runs next to your own Vortex as a copy that never touches it; a bad `--qa…` argument stops the app before it starts. Drive it with `scripts/qa`:

    scripts/qa build                       # make build, copied to build/qa/<run> (build/qa/latest)
    scripts/qa start A [-AppleLanguages '(uk)'] [--qa-reduce-motion] [--qa-release] [--qa-screens notch+plain]
    scripts/qa cmd A entry kind=notch      # prints the JSON reply; exit 1 on "ok": false, 2 on a timeout
    scripts/qa cmd A snapshot window=notch path=/tmp/home.png
    scripts/qa cmd A state path=/tmp/a.json
    scripts/qa stop A; scripts/qa kill A; scripts/qa reset A; scripts/qa list

- Data: everything in ~/Library/Application Support/Vortex QA/<name>/ (database, feature JSON, files, settings.json); QA's own files in its `.qa/`, fixtures in `fixtures/` (`screen.png` is what a capture sees). To start from given data, put files there before `start`, never links: a run with a link or hard link leading out of its folder refuses to start. UserDefaults is the `.check` build's, shared by all runs: keep run state in DataFolder.
- One run name per agent (or person): names are kept in lowercase, so A and a are one run. `start` and `list` print the app a run runs; `cmd`, `stop`, `kill` and `reset` refuse a run from another checkout unless `--other-checkout` comes first. A run that refuses to start says why, from its `.qa/launch.log`.
- Isolated: one instance per name; the MCP server on a port of its own (49152–65535, in its secrets.json, never 47823); no `…debug.*` notifications, commands only on `io.github.ortexisartem.vortex.qa.<name>`.
- Simulated: pasteboard and keychain in memory; shortcuts pressed only by `entry kind=hotkey`; keyboard lock (never a tap), screen capture, front window, text recognition and apps from fixtures; notifications, sounds, the login item, Finder, opened files and URLs only logged; commands never run; file panels never show; relaunch restarts the run with its arguments.
- Nothing shows: no menu bar icon or ears, windows off the displays (a task's whole screen too), never in front, no global monitors. No window can take the keyboard: each window class checks `QA.allowsKeyWindows` in `canBecomeKey`, and one that becomes key anyway is ordered out.
- Built in: `state [path=]`, `snapshot window=<id> path=<png>` (drawn by the app with `cacheDisplay`), `relaunch`, `quit`, `help`, `app activate=|quit=|frames=<bundle id>:<x,y,w,h;…>`, `sim [set k=v…|copy text=…|press notification= button=|shell match= exit= [stdout= stderr= delay= echo=true]|shell clear]`; a script whose delay reaches the command's time limit ends as the live client ends it: exit 143, timed out.
- The shell adds `entry kind=hover [ear=]|leave|ear id=|notch|menubar|menu item=open|settings|quit|hotkey id=|pointer inside=|outside|escape|drag|drop file=|open file=`, `tab id= [section=]`, `keyboard press=start|stop`, `screens set=`, `indicator`; features add theirs with `QA.register(command:)`, `QA.registerState(section:)` and `QA.registerWindow(id:)`, and give menu items an identifier.
- `state` lists violations: a window on a display (the guard, installed as the shell starts, orders it out), Vortex in front, a window with the keyboard, a call the simulation lacks. Files are written only inside the run's folder or a temporary one; `reset` deletes only inside "Vortex QA".
- Safety: `scripts/qa` starts only `make build` copies (bundle id ….check), through LaunchServices in the background. Never post `…debug.*`; never touch the user's Vortex, its data or its port.
