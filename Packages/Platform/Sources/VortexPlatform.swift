/// System clients live in this module: notch window, hotkeys, screen capture, pasteboard,
/// file watching, Keychain. Features reach the system only through these clients, declared
/// with `@DependencyClient`, so every feature can be tested with substituted clients.
public enum VortexPlatform {}
