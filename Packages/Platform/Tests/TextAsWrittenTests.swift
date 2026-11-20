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

  /// The warm-up's picture holds words Vision reads, so the warm-up loads what reads text, not only what finds it; and it
  /// ends without throwing.
  @Test
  func theWarmUpReadsWords() async throws {
    let picture = try #require(warmUpPicture())
    let text = try await TextRecognitionClient.liveValue.recognizeAsWritten(ScreenImage(cgImage: picture, scale: 2))
    #expect(text.contains("Vortex"), "\(text)")
    await TextRecognitionClient.liveValue.warmUp()
  }

  /// Many reads at once all end. Vision holds a thread for each read while it waits for work of its own on other
  /// threads: 32 reads at once, as tests running side by side make, once left no thread for that work, and none ended.
  /// The limit only stops a hang: in a run of every suite at once the reads wait their turns behind the other suites'
  /// for close to a minute.
  @Test(.timeLimit(.minutes(3)))
  func manyReadsAtOnceAllEnd() async throws {
    let chat = try Fixture.image("chat"), code = try Fixture.image("code")
    let reads = try await withThrowingTaskGroup(of: String.self) { group in
      for index in 0..<32 {
        group.addTask {
          index.isMultiple(of: 2)
            ? try await TextRecognitionClient.liveValue.recognize(chat)
            : try await TextRecognitionClient.liveValue.recognizeAsWritten(code)
        }
      }
      return try await group.reduce(into: [String]()) { $0.append($1) }
    }
    #expect(reads.count == 32)
    #expect(reads.allSatisfy { !$0.isEmpty })
  }

  /// Spaces come only between two lowercase letters, where the two reads agree on the letters on either side.
  @Test
  func onlyTheSpacesBetweenLowercaseLettersComeFromTheCorrectedRead() {
    #expect(spaced("brownfox jumps overthe lazy", as: "brown fox jumps over the lazy") == "brown fox jumps over the lazy")
    #expect(spaced("(Main.swift:42)", as: "(Main.swift: 42)") == "(Main.swift:42)")
    #expect(spaced("Line 01- The", as: "Line 01 - The") == "Line 01- The")
    #expect(spaced("error: cannot", as: "error:cannot") == "error: cannot")
    // A letter one read got wrong elsewhere doesn't keep the spaces from coming.
    #expect(spaced("Line 14-he quickbrown", as: "Line 14 - The quick brown") == "Line 14-he quick brown")
    #expect(spaced("", as: "a b") == "")
  }

  /// Code keeps its words whole: language correction parts camelCase, and a space it puts where a lowercase letter
  /// meets a capital, or between two capitals, never comes in.
  @Test
  func camelCaseWordsStayWhole() {
    #expect(
      spaced("getElementById querySelector addEventListener", as: "get Element By Id query Selector add Event Listener")
        == "getElementById querySelector addEventListener"
    )
    #expect(spaced("LastName FirstName", as: "LastName First Name") == "LastName FirstName")
    #expect(spaced("let userName = firstName", as: "let user Name = first Name") == "let userName = firstName")
    #expect(spaced("JSONDecoder NSTextView", as: "JSON Decoder NS Text View") == "JSONDecoder NSTextView")
  }

  /// Identifiers in the system font at 11, 12 and 13 pt, where Vision's correction parts `querySelector`: read as
  /// written, each stays one word.
  @Test
  func identifiersInSmallTextStayWhole() async throws {
    for size in [22.0, 24.0, 26.0] {
      let lines = ["getElementById querySelector addEventListener", "LastName FirstName"]
      let picture = TextTilesTests.picture(lines, width: 2_400, height: Int(size * 5), size: size, pitch: size * 1.6)
      let text = try await TextRecognitionClient.liveValue.recognizeAsWritten(picture)
      #expect(text.contains("querySelector") && text.contains("LastName FirstName"), "\(size / 2) pt: \(text)")
      #expect(text.split(separator: "\n").map { $0.split(separator: " ").count } == [3, 2], "\(size / 2) pt: \(text)")
    }
  }
}
