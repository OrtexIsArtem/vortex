import AppKit
import VortexShell

#if DEBUG
  // QA mode (`--qa <name>`, App/docs/README.md) replaces the system clients before anything reads one; a bad `--qa`
  // stops the app here. Without `--qa` nothing changes.
  ShellController.prepareQA()
#endif

// Vortex has no Dock icon and no main window (LSUIElement), so it starts from a plain AppKit entry point.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
