#if DEBUG
  import CoreGraphics
  import Foundation
  import ImageIO
  import Testing
  import VortexCore
  import VortexPlatform

  @testable import FeatureScreenText

  /// QA mode's fixture: what a capture sees in a QA run, read end to end with Apple Vision as plain Vortex reads it.
  @MainActor
  struct ScreenTextQATests {
    /// The parts of the fixture are where the state says, and Vision reads them: each QR code's payload, and the chat's
    /// lines, Ukrainian too.
    @Test
    func theFixturesCodesAndTextAreWhereItSays() async throws {
      let size = CGSize(width: 1512, height: 982)
      let (png, frames) = try ScreenTextModule.Fixture.draw(size: size, scale: 2, background: nil)
      let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
      let picture = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
      let image = ScreenImage(cgImage: picture, scale: 2)
      #expect(image.size == size)
      func part(_ name: String) throws -> ScreenImage {
        let frame = try #require(frames[name], "\(name)")
        return try #require(image.cropped(to: frame), "\(name)")
      }
      let recognition = TextRecognitionClient.liveValue
      for (name, payload) in [
        ("linkCode", ScreenTextModule.Fixture.link),
        ("textCode", ScreenTextModule.Fixture.text),
        ("wifiCode", ScreenTextModule.Fixture.wifi),
      ] {
        #expect(try await recognition.readQRCode(part(name)) == payload, "\(name)")
      }
      let text = try part("text")
      #expect(try await recognition.readQRCode(text) == nil)
      let lines = ScreenTextFeature.lines(of: try await recognition.recognize(text))
      #expect(lines.count == 3, "\(lines)")
      #expect(lines.first == ScreenTextModule.Fixture.lines.first)
      #expect(try await recognition.recognize(part("empty")).isEmpty)
    }

    /// The state names the phase and the message by kind, with its words left and right of the cutout.
    @Test
    func theStateDescribesTheMessageByKind() {
      let lines = ScreenTextModule.QAState.describe(.copiedLines(2), shownAt: nil, hiddenAt: nil)
      #expect(lines.kind == "copiedLines" && lines.left.count == 1 && lines.right.count == 1)
      let link = ScreenTextModule.QAState.describe(.copiedLink(host: "example.com"), shownAt: nil, hiddenAt: nil)
      #expect(link.kind == "copiedLink" && link.right == ["example.com"])
      #expect(ScreenTextModule.QAState.describe(.copiedCode, shownAt: nil, hiddenAt: nil).kind == "copiedCode")
      let nothing = ScreenTextModule.QAState.describe(.nothingFound, shownAt: nil, hiddenAt: nil)
      #expect(nothing.kind == "nothingFound" && nothing.right.isEmpty)
    }
  }
#endif
