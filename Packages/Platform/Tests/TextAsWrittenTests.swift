import Testing

@testable import VortexPlatform

/// Text read as written, without Vision's language correction, which puts a space after the colon in `Main.swift:42`:
/// code, paths and times come as they show.
struct TextAsWrittenTests {
  /// The tester's lines of Ukrainian, Russian, English and code, 1,400 × 350 px.
  @Test
  func codeAndPathsAreReadAsWritten() async throws {
    let text = try await TextRecognitionClient.liveValue.recognizeAsWritten(Fixture.image("code"))
    let lines = text.split(separator: "\n").map(String.init)
    #expect(lines.count == 5, "\(lines)")
    #expect(lines.contains("error: cannot find 'FooBar' in scope (Main.swift:42)"), "\(lines)")
    #expect(lines.contains("~/Library/Application Support/Vortex/clipboard.json"), "\(lines)")
    #expect(lines.contains("The quick brown fox jumps over 13 lazy dogs"), "\(lines)")
  }
}
