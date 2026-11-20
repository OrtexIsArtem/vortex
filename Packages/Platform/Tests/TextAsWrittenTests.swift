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

  /// The tester's 11 pt lines, the top of the screen: read as written alone, Vision drops a space between words in about
  /// a third of them ("brownfox jumps overthe"); the spaces a corrected read finds between two letters put them back.
  /// A letter Vision misreads, as in a line the picture's edge cuts, stays as read.
  @Test
  func smallTextKeepsTheSpacesBetweenWords() async throws {
    let text = try await TextRecognitionClient.liveValue.recognizeAsWritten(Fixture.image("dense-wide"))
    let numbered = text.split(separator: "\n").filter { $0.hasPrefix("Line ") }
    let glued = ["Thequick", "quickbrown", "brownfox", "foxjumps", "jumpsover", "overthe", "thelazy", "lazydog"]
    #expect(numbered.count >= 29, "\(numbered)")
    #expect(numbered.filter { line in glued.contains { line.contains($0) } } == [])
    let wordForWord = numbered.filter { $0.contains("The quick brown fox jumps over the lazy dog 0123456789") }
    #expect(wordForWord.count >= numbered.count - 2, "\(numbered.filter { !wordForWord.contains($0) })")
  }

  /// Spaces come only between two letters, where the two reads agree on the letters on either side.
  @Test
  func onlyTheSpacesBetweenLettersComeFromTheCorrectedRead() {
    #expect(spaced("brownfox jumps overthe lazy", as: "brown fox jumps over the lazy") == "brown fox jumps over the lazy")
    #expect(spaced("(Main.swift:42)", as: "(Main.swift: 42)") == "(Main.swift:42)")
    #expect(spaced("Line 01- The", as: "Line 01 - The") == "Line 01- The")
    #expect(spaced("error: cannot", as: "error:cannot") == "error: cannot")
    // A letter one read got wrong elsewhere doesn't keep the spaces from coming.
    #expect(spaced("Line 14-he quickbrown", as: "Line 14 - The quick brown") == "Line 14-he quick brown")
    #expect(spaced("", as: "a b") == "")
  }
}
