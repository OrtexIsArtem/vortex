import AppKit

// Vortex has no Dock icon and no main window (LSUIElement), so it starts from a plain AppKit entry point.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
