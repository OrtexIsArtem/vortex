/// Color theme of the app. `system` follows macOS.
public enum AppTheme: String, Codable, CaseIterable, Sendable {
  case system
  case light
  case dark
}

/// Interface language. `system` follows macOS; the others override it for Vortex only.
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
  case system
  case ukrainian = "uk"
  case english = "en"
}
